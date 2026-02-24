import Foundation
import GoogleSignIn
import Security

nonisolated enum AuthMethod: String, Codable, Sendable {
    case google
    case email
}

nonisolated struct AuthSession: Codable, Sendable {
    let userId: String
    let token: String
    let authMethod: AuthMethod
    let createdAt: Date
    let expiresAt: Date

    var isExpired: Bool { expiresAt < Date() }
    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 7 * 24 * 60 * 60 }
}

@Observable
final class AuthenticationService {
    var currentUser: GIDGoogleUser?
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
    private var emailUserProfile: UserProfile?
    private(set) var currentUserId: String?
    private(set) var backendToken: String?

    var userName: String {
        if authMethod == .email {
            return emailUserProfile?.name ?? ""
        }
        return currentUser?.profile?.name ?? ""
    }

    var userEmail: String {
        if authMethod == .email {
            return emailUserProfile?.email ?? ""
        }
        return currentUser?.profile?.email ?? ""
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
        if authMethod == .email { return nil }
        return currentUser?.profile?.imageURL(withDimension: 120)
    }

    private var backendAuthRetryCount: Int = 0
    private let maxBackendAuthRetries: Int = 3

    init() {
        configureGoogleSignIn()
        restorePreviousSignIn()
    }

    private var isGoogleConfigured: Bool = false

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

    // MARK: - Session Restore

    func restorePreviousSignIn() {
        isLoading = true

        if let session = KeychainService.loadSessionToken() {
            guard session.expiry > Date() else {
                KeychainService.clearSessionToken()
                UserDefaults.standard.removeObject(forKey: "sv_backend_token")
                isLoading = false
                return
            }

            let savedMethod = UserDefaults.standard.string(forKey: "sv_auth_method")
            let method = savedMethod.flatMap { AuthMethod(rawValue: $0) }

            if method == .email {
                if let profile = PersistenceService.shared.loadUserProfile(for: session.userId) {
                    emailUserProfile = profile
                    currentUserId = session.userId
                    authMethod = .email
                    isSignedIn = true
                    restoreBackendToken()
                    refreshSessionIfNeeded()
                }
                isLoading = false
                return
            }

            if method == .google {
                if isGoogleConfigured, GIDSignIn.sharedInstance.hasPreviousSignIn() {
                    GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
                        Task { @MainActor in
                            guard let self else { return }
                            if let user {
                                self.currentUser = user
                                let userId = user.userID ?? session.userId
                                self.currentUserId = userId
                                self.authMethod = .google
                                self.isSignedIn = true
                                self.persistGoogleUserProfile()
                                self.restoreBackendToken()
                                self.authenticateGoogleWithBackend()
                            } else if let profile = PersistenceService.shared.loadUserProfile(for: session.userId) {
                                self.emailUserProfile = profile
                                self.currentUserId = session.userId
                                self.authMethod = .google
                                self.isSignedIn = true
                                self.restoreBackendToken()
                            }
                            self.isLoading = false
                        }
                    }
                    return
                } else if let profile = PersistenceService.shared.loadUserProfile(for: session.userId) {
                    currentUserId = session.userId
                    authMethod = .google
                    isSignedIn = true
                    restoreBackendToken()
                    isLoading = false
                    return
                }
            }
        }

        if isGoogleConfigured, GIDSignIn.sharedInstance.hasPreviousSignIn() {
            GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let user {
                        self.currentUser = user
                        let userId = user.userID ?? UUID().uuidString
                        self.currentUserId = userId
                        self.authMethod = .google
                        self.isSignedIn = true
                        self.createSession(userId: userId, method: .google)
                        self.persistGoogleUserProfile()
                        self.authenticateGoogleWithBackend()
                    }
                    self.isLoading = false
                }
            }
        } else {
            isLoading = false
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

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    if (error as NSError).code != GIDSignInError.canceled.rawValue {
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }
                guard let user = result?.user else { return }
                self.currentUser = user
                let userId = user.userID ?? UUID().uuidString
                self.currentUserId = userId
                self.authMethod = .google
                UserDefaults.standard.set(AuthMethod.google.rawValue, forKey: "sv_auth_method")
                self.createSession(userId: userId, method: .google)
                self.persistGoogleUserProfile()
                self.isSignedIn = true
                self.authenticateGoogleWithBackend()
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

    func validateResetFields(email: String, newPassword: String, confirmPassword: String) -> Bool {
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

        if newPassword.isEmpty {
            passwordError = "New password is required"
            valid = false
        } else if !isStrongPassword(newPassword) {
            passwordError = "Must be 8+ characters with a letter and number"
            valid = false
        }

        if confirmPassword.isEmpty {
            confirmPasswordError = "Please confirm your password"
            valid = false
        } else if newPassword != confirmPassword {
            confirmPasswordError = "Passwords do not match"
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
        let initials = "\(capitalizedFirst.prefix(1))\(capitalizedLast.prefix(1))".uppercased()

        if APIService.shared.isConfigured {
            Task {
                await registerWithBackendFirst(name: fullName, email: trimmedEmail, password: password, initials: initials)
            }
        } else {
            completeLocalSignUp(name: fullName, email: trimmedEmail, password: password, initials: initials)
        }
    }

    private func completeLocalSignUp(name: String, email: String, password: String, initials: String, userId: String? = nil) {
        let resolvedUserId = userId ?? UUID().uuidString

        _ = KeychainService.savePassword(password, for: email)

        let profile = UserProfile(
            id: resolvedUserId,
            name: name,
            email: email,
            initials: initials,
            profileImageURL: nil
        )

        PersistenceService.shared.saveUserProfile(profile, for: resolvedUserId)
        PersistenceService.shared.saveEmailToUserIdMapping(email: email, userId: resolvedUserId)
        emailUserProfile = profile
        currentUserId = resolvedUserId
        isSignedIn = true
        authMethod = .email
        isSubmitting = false
        UserDefaults.standard.set(AuthMethod.email.rawValue, forKey: "sv_auth_method")
        createSession(userId: resolvedUserId, method: .email)
    }

    private func registerWithBackendFirst(name: String, email: String, password: String, initials: String) async {
        do {
            let response = try await APIService.shared.register(name: name, email: email, password: password)
            if response.success, let token = response.token {
                let userId = response.userId ?? UUID().uuidString
                backendToken = token
                UserDefaults.standard.set(token, forKey: "sv_backend_token")
                APIService.shared.setAuth(token: token, userId: userId)
                completeLocalSignUp(name: name, email: email, password: password, initials: initials, userId: userId)
            } else if let serverError = response.error {
                if serverError.lowercased().contains("already exists") {
                    emailError = "An account with this email already exists"
                    errorMessage = "Please sign in instead."
                } else {
                    errorMessage = serverError
                }
                isSubmitting = false
            } else {
                errorMessage = "Unable to create account. Please try again."
                isSubmitting = false
            }
        } catch {
            completeLocalSignUp(name: name, email: email, password: password, initials: initials)
        }
    }

    // MARK: - Email/Password Sign In

    func signInWithEmail(email: String, password: String) {
        guard validateSignInFields(email: email, password: password) else { return }
        isSubmitting = true

        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

        guard let storedPassword = KeychainService.loadPassword(for: trimmedEmail) else {
            emailError = "No account found with this email"
            errorMessage = "Please sign up instead."
            isSubmitting = false
            return
        }

        guard storedPassword == password else {
            passwordError = "Incorrect password"
            isSubmitting = false
            return
        }

        let userId: String
        if let mappedId = PersistenceService.shared.loadUserIdForEmail(trimmedEmail) {
            userId = mappedId
        } else {
            userId = UUID().uuidString
            PersistenceService.shared.saveEmailToUserIdMapping(email: trimmedEmail, userId: userId)
        }

        if let profile = PersistenceService.shared.loadUserProfile(for: userId) {
            emailUserProfile = profile
        } else {
            let profile = UserProfile(
                id: userId,
                name: trimmedEmail.components(separatedBy: "@").first ?? "User",
                email: trimmedEmail,
                initials: String(trimmedEmail.prefix(2)).uppercased(),
                profileImageURL: nil
            )
            PersistenceService.shared.saveUserProfile(profile, for: userId)
            emailUserProfile = profile
        }

        currentUserId = userId
        isSignedIn = true
        authMethod = .email
        isSubmitting = false
        UserDefaults.standard.set(AuthMethod.email.rawValue, forKey: "sv_auth_method")
        createSession(userId: userId, method: .email)

        loginWithBackend(email: trimmedEmail, password: password, userId: userId)
    }

    // MARK: - Password Reset

    func resetPassword(email: String, newPassword: String, confirmPassword: String) {
        guard validateResetFields(email: email, newPassword: newPassword, confirmPassword: confirmPassword) else { return }
        isSubmitting = true

        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

        guard KeychainService.loadPassword(for: trimmedEmail) != nil else {
            emailError = "No account found with this email"
            isSubmitting = false
            return
        }

        guard KeychainService.updatePassword(newPassword, for: trimmedEmail) else {
            errorMessage = "Unable to reset password. Please try again."
            isSubmitting = false
            return
        }

        isSubmitting = false
        passwordResetSuccess = true
        showPasswordReset = false
    }

    // MARK: - Sign Out

    func signOut() {
        logoutFromBackend()
        if authMethod == .google {
            GIDSignIn.sharedInstance.signOut()
            currentUser = nil
        }
        emailUserProfile = nil
        currentUserId = nil
        backendToken = nil
        isSignedIn = false
        authMethod = nil
        KeychainService.clearSessionToken()
        UserDefaults.standard.removeObject(forKey: "sv_auth_method")
        UserDefaults.standard.removeObject(forKey: "sv_backend_token")
    }

    func deleteAccount() {
        let email = userEmail
        let userId = currentUserId

        signOut()

        if !email.isEmpty {
            KeychainService.deletePassword(for: email)
        }
        if let userId {
            PersistenceService.shared.clearUserData(for: userId)
        }
    }

    // MARK: - Session Management

    private func createSession(userId: String, method: AuthMethod) {
        let token = KeychainService.generateToken()
        let expiry = Date().addingTimeInterval(30 * 24 * 60 * 60)
        _ = KeychainService.saveSessionToken(token, userId: userId, expiry: expiry)
    }

    private func refreshSessionIfNeeded() {
        guard let session = KeychainService.loadSessionToken(),
              Date(timeIntervalSince1970: 0) < session.expiry else { return }

        let timeToExpiry = session.expiry.timeIntervalSinceNow
        if timeToExpiry < 7 * 24 * 60 * 60 {
            _ = KeychainService.refreshSessionToken()
        }
    }

    func validateSession() -> Bool {
        guard let session = KeychainService.loadSessionToken() else {
            if isSignedIn && authMethod == .email {
                signOut()
            }
            return false
        }
        refreshSessionIfNeeded()
        return session.expiry > Date()
    }

    // MARK: - Helpers

    private func persistGoogleUserProfile() {
        guard let user = currentUser, let profile = user.profile else { return }
        let userId = user.userID ?? UUID().uuidString
        let initials: String = {
            let parts = profile.name.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            }
            return String(profile.name.prefix(2)).uppercased()
        }()
        let userProfile = UserProfile(
            id: userId,
            name: profile.name,
            email: profile.email,
            initials: initials,
            profileImageURL: profile.imageURL(withDimension: 120)?.absoluteString
        )
        PersistenceService.shared.saveUserProfile(userProfile, for: userId)
    }

    func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        return email.wholeMatch(of: regex) != nil
    }

    private func isStrongPassword(_ password: String) -> Bool {
        guard password.count >= 8 else { return false }
        let hasLetter = password.contains(where: \.isLetter)
        let hasNumber = password.contains(where: \.isNumber)
        return hasLetter && hasNumber
    }

    // MARK: - Backend Auth



    private func loginWithBackend(email: String, password: String, userId: String) {
        guard APIService.shared.isConfigured else { return }
        backendAuthRetryCount = 0
        Task {
            await performBackendAuth({
                try await APIService.shared.login(email: email, password: password)
            }, userId: userId)
        }
    }

    private func authenticateGoogleWithBackend() {
        guard APIService.shared.isConfigured else { return }
        guard let user = currentUser, let profile = user.profile else { return }
        let googleUserId = user.userID ?? UUID().uuidString
        backendAuthRetryCount = 0
        Task {
            await performBackendAuth({
                try await APIService.shared.googleAuth(
                    googleUserId: googleUserId,
                    name: profile.name,
                    email: profile.email
                )
            }, userId: googleUserId)
        }
    }

    private func performBackendAuth(_ authCall: () async throws -> AuthResponse, userId: String) async {
        var lastError: Error?
        for attempt in 0...maxBackendAuthRetries {
            do {
                let response = try await authCall()
                if response.success, let token = response.token {
                    backendToken = token
                    UserDefaults.standard.set(token, forKey: "sv_backend_token")
                    APIService.shared.setAuth(token: token, userId: response.userId ?? userId)
                    return
                } else if let serverError = response.error {
                    errorMessage = serverError
                    return
                }
            } catch let error as APIError {
                lastError = error
                if error.isRetryable && attempt < maxBackendAuthRetries {
                    let delay = Double(1 << attempt) * 0.5
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                if case .validationError(let msg) = error {
                    errorMessage = msg
                } else if case .unauthorized = error {
                    errorMessage = "Session expired. Please sign in again."
                } else {
                    errorMessage = "Unable to connect to server. Your data is saved locally."
                }
                return
            } catch {
                lastError = error
                if attempt < maxBackendAuthRetries {
                    let delay = Double(1 << attempt) * 0.5
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                errorMessage = "Unable to connect to server. Your data is saved locally."
                return
            }
        }
    }

    private func logoutFromBackend() {
        guard APIService.shared.isConfigured, backendToken != nil else { return }
        Task {
            try? await APIService.shared.logout()
        }
    }

    func restoreBackendToken() {
        guard let token = UserDefaults.standard.string(forKey: "sv_backend_token"), !token.isEmpty else { return }
        backendToken = token
        guard let userId = currentUserId, !userId.isEmpty else { return }
        APIService.shared.setAuth(token: token, userId: userId)
    }

    func validateAndRefreshSession() {
        guard isSignedIn else { return }
        guard let session = KeychainService.loadSessionToken() else {
            signOut()
            return
        }
        if session.expiry < Date() {
            signOut()
            errorMessage = "Your session has expired. Please sign in again."
            return
        }
        refreshSessionIfNeeded()

        if backendToken == nil, APIService.shared.isConfigured {
            retryBackendAuthIfNeeded()
        }
    }

    private func retryBackendAuthIfNeeded() {
        guard let method = authMethod else { return }
        switch method {
        case .google:
            authenticateGoogleWithBackend()
        case .email:
            break
        }
    }
}
