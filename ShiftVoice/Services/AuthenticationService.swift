import Foundation
import FirebaseAuth
import GoogleSignIn
import Security

nonisolated enum AuthMethod: String, Codable, Sendable {
    case google
    case email
}

@Observable
final class AuthenticationService {
    var isSignedIn: Bool = false
    var isLoading: Bool = true
    var isSubmitting: Bool = false
    var errorMessage: String?
    var showPasswordReset: Bool = false
    var passwordResetSuccess: Bool = false

    var firstNameError: String?
    var lastNameError: String?
    var emailError: String?
    var passwordError: String?
    var confirmPasswordError: String?

    private var authMethod: AuthMethod?
    private(set) var currentUserId: String?
    private(set) var backendToken: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    var userName: String {
        guard let user = Auth.auth().currentUser else { return "" }
        return user.displayName ?? ""
    }

    var userEmail: String {
        guard let user = Auth.auth().currentUser else { return "" }
        return user.email ?? ""
    }

    var userInitials: String {
        let name = userName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var userProfileImageURL: URL? {
        Auth.auth().currentUser?.photoURL
    }

    private var backendAuthRetryCount: Int = 0
    private let maxBackendAuthRetries: Int = 3
    private var isGoogleConfigured: Bool = false
    private(set) var backendAuthFailed: Bool = false
    private var isRetryingBackendAuth: Bool = false

    init() {
        configureGoogleSignIn()
        setupAuthStateListener()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    private func configureGoogleSignIn() {
        let clientID = Config.GOOGLE_CLIENT_ID
        guard !clientID.isEmpty,
              clientID != "GOOGLE_CLIENT_ID",
              clientID.contains(".") else {
            isGoogleConfigured = false
            return
        }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        isGoogleConfigured = true
    }

    private func setupAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if let user {
                    self.currentUserId = user.uid
                    self.isSignedIn = true
                    self.authenticateWithBackend(firebaseUser: user)
                } else {
                    if self.isSignedIn {
                        self.currentUserId = nil
                        self.backendToken = nil
                        self.isSignedIn = false
                    }
                }
                self.isLoading = false
            }
        }
    }

    // MARK: - Google Sign In

    func signInWithGoogle() {
        guard isGoogleConfigured else {
            errorMessage = "Google Sign-In is not configured. Please use email sign-in."
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to find root view controller"
            return
        }

        errorMessage = nil
        isSubmitting = true

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    if (error as NSError).code != GIDSignInError.canceled.rawValue {
                        self.errorMessage = error.localizedDescription
                    }
                    self.isSubmitting = false
                    return
                }
                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    self.errorMessage = "Unable to get Google credentials"
                    self.isSubmitting = false
                    return
                }

                let credential = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: user.accessToken.tokenString
                )

                do {
                    let authResult = try await Auth.auth().signIn(with: credential)
                    self.authMethod = .google
                    UserDefaults.standard.set(AuthMethod.google.rawValue, forKey: "sv_auth_method")
                    self.currentUserId = authResult.user.uid
                    self.isSignedIn = true
                    self.persistUserProfile(firebaseUser: authResult.user)
                } catch {
                    self.errorMessage = error.localizedDescription
                }
                self.isSubmitting = false
            }
        }
    }

    // MARK: - Email/Password Sign Up

    func clearFieldErrors() {
        firstNameError = nil
        lastNameError = nil
        emailError = nil
        passwordError = nil
        confirmPasswordError = nil
        errorMessage = nil
    }

    private func capitalizeName(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }

    func validateSignUpFields(firstName: String, lastName: String, email: String, password: String) -> Bool {
        clearFieldErrors()
        var valid = true

        let trimmedFirst = firstName.trimmingCharacters(in: .whitespaces)
        if trimmedFirst.isEmpty {
            firstNameError = "First name is required"
            valid = false
        } else if trimmedFirst.count < 2 {
            firstNameError = "Must be at least 2 characters"
            valid = false
        }

        let trimmedLast = lastName.trimmingCharacters(in: .whitespaces)
        if trimmedLast.isEmpty {
            lastNameError = "Last name is required"
            valid = false
        } else if trimmedLast.count < 2 {
            lastNameError = "Must be at least 2 characters"
            valid = false
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if trimmedEmail.isEmpty {
            emailError = "Email is required"
            valid = false
        } else if !isValidEmail(trimmedEmail) {
            emailError = "Enter a valid email address"
            valid = false
        }

        if password.isEmpty {
            passwordError = "Password is required"
            valid = false
        } else if password.count < 8 {
            passwordError = "Must be at least 8 characters"
            valid = false
        } else if !password.contains(where: \.isLetter) {
            passwordError = "Must contain at least one letter"
            valid = false
        } else if !password.contains(where: \.isNumber) {
            passwordError = "Must contain at least one number"
            valid = false
        }

        return valid
    }

    func validateSignInFields(email: String, password: String) -> Bool {
        clearFieldErrors()
        var valid = true

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if trimmedEmail.isEmpty {
            emailError = "Email is required"
            valid = false
        } else if !isValidEmail(trimmedEmail) {
            emailError = "Enter a valid email address"
            valid = false
        }

        if password.isEmpty {
            passwordError = "Password is required"
            valid = false
        }

        return valid
    }

    func signUpWithEmail(firstName: String, lastName: String, email: String, password: String) {
        guard validateSignUpFields(firstName: firstName, lastName: lastName, email: email, password: password) else { return }
        isSubmitting = true

        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        let capitalizedFirst = capitalizeName(firstName)
        let capitalizedLast = capitalizeName(lastName)
        let fullName = "\(capitalizedFirst) \(capitalizedLast)"

        Task {
            do {
                let authResult = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)

                let changeRequest = authResult.user.createProfileChangeRequest()
                changeRequest.displayName = fullName
                try await changeRequest.commitChanges()

                self.authMethod = .email
                UserDefaults.standard.set(AuthMethod.email.rawValue, forKey: "sv_auth_method")
                self.currentUserId = authResult.user.uid
                self.isSignedIn = true
                self.persistUserProfile(firebaseUser: authResult.user, overrideName: fullName)
            } catch let error as NSError {
                self.handleFirebaseAuthError(error)
            }
            self.isSubmitting = false
        }
    }

    // MARK: - Email/Password Sign In

    func signInWithEmail(email: String, password: String) {
        guard validateSignInFields(email: email, password: password) else { return }
        isSubmitting = true

        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

        Task {
            do {
                let authResult = try await Auth.auth().signIn(withEmail: trimmedEmail, password: password)
                self.authMethod = .email
                UserDefaults.standard.set(AuthMethod.email.rawValue, forKey: "sv_auth_method")
                self.currentUserId = authResult.user.uid
                self.isSignedIn = true
                self.persistUserProfile(firebaseUser: authResult.user)
            } catch let error as NSError {
                self.handleFirebaseAuthError(error)
            }
            self.isSubmitting = false
        }
    }

    // MARK: - Password Reset

    func sendPasswordReset(email: String) {
        clearFieldErrors()
        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

        guard !trimmedEmail.isEmpty else {
            emailError = "Email is required"
            return
        }
        guard isValidEmail(trimmedEmail) else {
            emailError = "Enter a valid email address"
            return
        }

        isSubmitting = true

        Task {
            do {
                try await Auth.auth().sendPasswordReset(withEmail: trimmedEmail)
                self.passwordResetSuccess = true
                self.showPasswordReset = false
            } catch let error as NSError {
                self.handleFirebaseAuthError(error)
            }
            self.isSubmitting = false
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            errorMessage = "Unable to sign out. Please try again."
            return
        }
        currentUserId = nil
        backendToken = nil
        isSignedIn = false
        authMethod = nil
        UserDefaults.standard.removeObject(forKey: "sv_auth_method")
        KeychainService.clearBackendToken()
    }

    func deleteAccount(password: String? = nil) {
        guard let user = Auth.auth().currentUser else {
            signOut()
            return
        }

        isSubmitting = true

        Task {
            do {
                let savedMethod = UserDefaults.standard.string(forKey: "sv_auth_method")
                if savedMethod == AuthMethod.email.rawValue {
                    guard let password, !password.isEmpty else {
                        errorMessage = "Password is required to delete your account."
                        isSubmitting = false
                        return
                    }
                    guard let email = user.email else {
                        errorMessage = "Unable to verify account. Please sign in again."
                        isSubmitting = false
                        return
                    }
                    let credential = EmailAuthProvider.credential(withEmail: email, password: password)
                    try await user.reauthenticate(with: credential)
                } else if savedMethod == AuthMethod.google.rawValue {
                    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let rootVC = windowScene.windows.first?.rootViewController else {
                        errorMessage = "Unable to verify account."
                        isSubmitting = false
                        return
                    }
                    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
                    guard let idToken = result.user.idToken?.tokenString else {
                        errorMessage = "Unable to get Google credentials."
                        isSubmitting = false
                        return
                    }
                    let credential = GoogleAuthProvider.credential(
                        withIDToken: idToken,
                        accessToken: result.user.accessToken.tokenString
                    )
                    try await user.reauthenticate(with: credential)
                }

                let userId = user.uid
                try await user.delete()

                self.currentUserId = nil
                self.backendToken = nil
                self.isSignedIn = false
                self.authMethod = nil
                UserDefaults.standard.removeObject(forKey: "sv_auth_method")
                KeychainService.clearBackendToken()
                FirestoreService.shared.deleteUserData(userId)
            } catch let error as NSError {
                let code = AuthErrorCode(rawValue: error.code)
                if code == .wrongPassword || code == .invalidCredential {
                    self.errorMessage = "Incorrect password. Please try again."
                } else if code == .requiresRecentLogin {
                    self.errorMessage = "Please sign in again to delete your account."
                } else {
                    self.errorMessage = "Unable to delete account: \(error.localizedDescription)"
                }
            }
            self.isSubmitting = false
        }
    }

    var isEmailAuth: Bool {
        UserDefaults.standard.string(forKey: "sv_auth_method") == AuthMethod.email.rawValue
    }

    // MARK: - URL Handling

    func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Session Validation

    func validateAndRefreshSession() {
        guard isSignedIn, let user = Auth.auth().currentUser else { return }
        Task {
            do {
                let token = try await user.getIDToken()
                if self.backendToken == nil, APIService.shared.isConfigured {
                    self.authenticateWithBackend(firebaseUser: user)
                }
                _ = token
            } catch {
                self.signOut()
                self.errorMessage = "Your session has expired. Please sign in again."
            }
        }
    }

    // MARK: - Backend Auth

    private func authenticateWithBackend(firebaseUser user: FirebaseAuth.User) {
        guard APIService.shared.isConfigured else { return }
        backendAuthRetryCount = 0

        Task {
            do {
                let idToken = try await user.getIDToken()
                let name = user.displayName ?? ""
                let email = user.email ?? ""
                let uid = user.uid

                await performBackendAuth({
                    try await APIService.shared.firebaseAuth(
                        idToken: idToken,
                        uid: uid,
                        name: name,
                        email: email
                    )
                }, userId: uid)
            } catch {
                self.backendAuthFailed = true
            }
        }
    }

    func retryBackendAuthIfNeeded() async -> Bool {
        guard backendAuthFailed || backendToken == nil else { return true }
        guard !isRetryingBackendAuth else { return false }
        guard let user = Auth.auth().currentUser else { return false }
        guard APIService.shared.isConfigured else { return false }

        isRetryingBackendAuth = true
        defer { isRetryingBackendAuth = false }

        do {
            let idToken = try await user.getIDToken()
            let response = try await APIService.shared.firebaseAuth(
                idToken: idToken,
                uid: user.uid,
                name: user.displayName ?? "",
                email: user.email ?? ""
            )
            if response.success, let token = response.token {
                backendToken = token
                backendAuthFailed = false
                _ = KeychainService.saveBackendToken(token)
                APIService.shared.setAuth(token: token, userId: response.userId ?? user.uid)
                return true
            }
        } catch {
            backendAuthFailed = true
        }
        return false
    }

    private func performBackendAuth(_ authCall: () async throws -> AuthResponse, userId: String) async {
        for attempt in 0...maxBackendAuthRetries {
            do {
                let response = try await authCall()
                if response.success, let token = response.token {
                    backendToken = token
                    backendAuthFailed = false
                    _ = KeychainService.saveBackendToken(token)
                    APIService.shared.setAuth(token: token, userId: response.userId ?? userId)
                    return
                } else if let serverError = response.error {
                    errorMessage = serverError
                    return
                }
            } catch let error as APIError {
                if error.isRetryable && attempt < maxBackendAuthRetries {
                    let delay = Double(1 << attempt) * 0.5
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                return
            } catch {
                if attempt < maxBackendAuthRetries {
                    let delay = Double(1 << attempt) * 0.5
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                return
            }
        }
    }

    func restoreBackendToken() {
        guard let token = KeychainService.loadBackendToken(), !token.isEmpty else { return }
        backendToken = token
        guard let userId = currentUserId, !userId.isEmpty else { return }
        APIService.shared.setAuth(token: token, userId: userId)
    }

    // MARK: - Helpers

    private func persistUserProfile(firebaseUser user: FirebaseAuth.User, overrideName: String? = nil) {
        let name = overrideName ?? user.displayName ?? ""
        let email = user.email ?? ""
        let initials: String = {
            let parts = name.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }()
        let profile = UserProfile(
            id: user.uid,
            name: name,
            email: email,
            initials: initials,
            profileImageURL: user.photoURL?.absoluteString
        )
        FirestoreService.shared.saveUserProfile(profile)
    }

    private func handleFirebaseAuthError(_ error: NSError) {
        let code = AuthErrorCode(rawValue: error.code)
        switch code {
        case .emailAlreadyInUse:
            emailError = "An account with this email already exists"
            errorMessage = "Please sign in instead."
        case .invalidEmail:
            emailError = "Enter a valid email address"
        case .wrongPassword, .invalidCredential:
            passwordError = "Incorrect email or password"
        case .userNotFound:
            emailError = "No account found with this email"
            errorMessage = "Please sign up instead."
        case .weakPassword:
            passwordError = "Password is too weak"
        case .networkError:
            errorMessage = "Network error. Please check your connection."
        case .tooManyRequests:
            errorMessage = "Too many attempts. Please try again later."
        case .userDisabled:
            errorMessage = "This account has been disabled."
        case .requiresRecentLogin:
            errorMessage = "Please sign in again to complete this action."
        default:
            errorMessage = error.localizedDescription
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        return email.wholeMatch(of: regex) != nil
    }
}
