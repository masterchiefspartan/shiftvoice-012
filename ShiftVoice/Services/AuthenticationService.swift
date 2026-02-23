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

    var nameError: String?
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

    init() {
        configureGoogleSignIn()
        restoreBackendToken()
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
            let savedMethod = UserDefaults.standard.string(forKey: "sv_auth_method")
            let method = savedMethod.flatMap { AuthMethod(rawValue: $0) }

            if method == .email {
                if let profile = PersistenceService.shared.loadUserProfile(for: session.userId) {
                    emailUserProfile = profile
                    currentUserId = session.userId
                    authMethod = .email
                    isSignedIn = true
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
                                self.authenticateGoogleWithBackend()
                            } else if let profile = PersistenceService.shared.loadUserProfile(for: session.userId) {
                                self.emailUserProfile = profile
                                self.currentUserId = session.userId
                                self.authMethod = .google
                                self.isSignedIn = true
                            }
                            self.isLoading = false
                        }
                    }
                    return
                } else if let profile = PersistenceService.shared.loadUserProfile(for: session.userId) {
                    currentUserId = session.userId
                    authMethod = .google
                    isSignedIn = true
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
        nameError = nil
        emailError = nil
        passwordError = nil
        confirmPasswordError = nil
        errorMessage = nil
    }

    func validateSignUpFields(name: String, email: String, password: String) -> Bool {
        clearFieldErrors()
        var valid = true

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            nameError = "Name is required"
            valid = false
        } else if trimmedName.count < 2 {
            nameError = "Name must be at least 2 characters"
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

    func signUpWithEmail(name: String, email: String, password: String) {
        guard validateSignUpFields(name: name, email: email, password: password) else { return }
        isSubmitting = true

        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if KeychainService.loadPassword(for: trimmedEmail) != nil {
            emailError = "An account with this email already exists"
            errorMessage = "Please sign in instead."
            isSubmitting = false
            return
        }

        guard KeychainService.savePassword(password, for: trimmedEmail) else {
            errorMessage = "Unable to create account. Please try again."
            isSubmitting = false
            return
        }

        let userId = UUID().uuidString
        let initials: String = {
            let parts = name.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }()

        let profile = UserProfile(
            id: userId,
            name: trimmedName,
            email: trimmedEmail,
            initials: initials,
            profileImageURL: nil
        )

        PersistenceService.shared.saveUserProfile(profile, for: userId)
        PersistenceService.shared.saveEmailToUserIdMapping(email: trimmedEmail, userId: userId)
        emailUserProfile = profile
        currentUserId = userId
        isSignedIn = true
        authMethod = .email
        isSubmitting = false
        UserDefaults.standard.set(AuthMethod.email.rawValue, forKey: "sv_auth_method")
        createSession(userId: userId, method: .email)

        registerWithBackend(name: trimmedName, email: trimmedEmail, password: password, userId: userId)
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

    private func registerWithBackend(name: String, email: String, password: String, userId: String) {
        guard APIService.shared.isConfigured else { return }
        Task {
            do {
                let response = try await APIService.shared.register(name: name, email: email, password: password)
                if response.success, let token = response.token {
                    backendToken = token
                    UserDefaults.standard.set(token, forKey: "sv_backend_token")
                    APIService.shared.setAuth(token: token, userId: response.userId ?? userId)
                }
            } catch {
                print("Backend register error: \(error.localizedDescription)")
            }
        }
    }

    private func loginWithBackend(email: String, password: String, userId: String) {
        guard APIService.shared.isConfigured else { return }
        Task {
            do {
                let response = try await APIService.shared.login(email: email, password: password)
                if response.success, let token = response.token {
                    backendToken = token
                    UserDefaults.standard.set(token, forKey: "sv_backend_token")
                    APIService.shared.setAuth(token: token, userId: response.userId ?? userId)
                }
            } catch {
                print("Backend login error: \(error.localizedDescription)")
            }
        }
    }

    private func authenticateGoogleWithBackend() {
        guard APIService.shared.isConfigured else { return }
        guard let user = currentUser, let profile = user.profile else { return }
        let googleUserId = user.userID ?? UUID().uuidString
        Task {
            do {
                let response = try await APIService.shared.googleAuth(
                    googleUserId: googleUserId,
                    name: profile.name,
                    email: profile.email
                )
                if response.success, let token = response.token {
                    backendToken = token
                    UserDefaults.standard.set(token, forKey: "sv_backend_token")
                    APIService.shared.setAuth(token: token, userId: response.userId ?? googleUserId)
                }
            } catch {
                print("Backend Google auth error: \(error.localizedDescription)")
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
        if let token = UserDefaults.standard.string(forKey: "sv_backend_token"), !token.isEmpty {
            backendToken = token
            if let userId = currentUserId {
                APIService.shared.setAuth(token: token, userId: userId)
            }
        }
    }
}
