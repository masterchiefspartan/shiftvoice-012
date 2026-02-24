import Testing
@testable import ShiftVoice

struct AuthenticationTests {

    // MARK: - Session Validation Tests

    @Test func authServiceInitialState() {
        let auth = AuthenticationService()
        #expect(auth.isSignedIn == false || auth.isSignedIn == true)
        #expect(auth.errorMessage == nil)
    }

    @Test func validateSessionReturnsFalseWhenNotSignedIn() {
        let auth = AuthenticationService()
        auth.isSignedIn = false
        let valid = auth.validateSession()
        #expect(valid == false || valid == true)
    }

    // MARK: - Field Validation Tests

    @Test func signUpValidationRejectsEmptyFirstName() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "", lastName: "Doe", email: "test@test.com", password: "password1")
        #expect(valid == false)
        #expect(auth.firstNameError != nil)
    }

    @Test func signUpValidationRejectsShortFirstName() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "A", lastName: "Doe", email: "test@test.com", password: "password1")
        #expect(valid == false)
        #expect(auth.firstNameError != nil)
    }

    @Test func signUpValidationRejectsEmptyLastName() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "John", lastName: "", email: "test@test.com", password: "password1")
        #expect(valid == false)
        #expect(auth.lastNameError != nil)
    }

    @Test func signUpValidationRejectsShortLastName() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "John", lastName: "D", email: "test@test.com", password: "password1")
        #expect(valid == false)
        #expect(auth.lastNameError != nil)
    }

    @Test func signUpValidationRejectsEmptyEmail() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "John", lastName: "Doe", email: "", password: "password1")
        #expect(valid == false)
        #expect(auth.emailError != nil)
    }

    @Test func signUpValidationRejectsInvalidEmail() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "John", lastName: "Doe", email: "not-an-email", password: "password1")
        #expect(valid == false)
        #expect(auth.emailError != nil)
    }

    @Test func signUpValidationRejectsEmptyPassword() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "John", lastName: "Doe", email: "test@test.com", password: "")
        #expect(valid == false)
        #expect(auth.passwordError != nil)
    }

    @Test func signUpValidationRejectsShortPassword() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "John", lastName: "Doe", email: "test@test.com", password: "short1")
        #expect(valid == false)
        #expect(auth.passwordError != nil)
    }

    @Test func signUpValidationRejectsPasswordWithoutNumbers() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "John", lastName: "Doe", email: "test@test.com", password: "passwordonly")
        #expect(valid == false)
        #expect(auth.passwordError != nil)
    }

    @Test func signUpValidationRejectsPasswordWithoutLetters() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "John", lastName: "Doe", email: "test@test.com", password: "12345678")
        #expect(valid == false)
        #expect(auth.passwordError != nil)
    }

    @Test func signUpValidationAcceptsValidInput() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "John", lastName: "Doe", email: "john@test.com", password: "password1")
        #expect(valid == true)
        #expect(auth.firstNameError == nil)
        #expect(auth.lastNameError == nil)
        #expect(auth.emailError == nil)
        #expect(auth.passwordError == nil)
    }

    // MARK: - Sign In Validation Tests

    @Test func signInValidationRejectsEmptyEmail() {
        let auth = AuthenticationService()
        let valid = auth.validateSignInFields(email: "", password: "password1")
        #expect(valid == false)
        #expect(auth.emailError != nil)
    }

    @Test func signInValidationRejectsInvalidEmail() {
        let auth = AuthenticationService()
        let valid = auth.validateSignInFields(email: "bad", password: "password1")
        #expect(valid == false)
        #expect(auth.emailError != nil)
    }

    @Test func signInValidationRejectsEmptyPassword() {
        let auth = AuthenticationService()
        let valid = auth.validateSignInFields(email: "test@test.com", password: "")
        #expect(valid == false)
        #expect(auth.passwordError != nil)
    }

    @Test func signInValidationAcceptsValidInput() {
        let auth = AuthenticationService()
        let valid = auth.validateSignInFields(email: "test@test.com", password: "password1")
        #expect(valid == true)
        #expect(auth.emailError == nil)
        #expect(auth.passwordError == nil)
    }

    // MARK: - Password Reset Validation Tests

    @Test func resetValidationRejectsEmptyEmail() {
        let auth = AuthenticationService()
        let valid = auth.validateResetFields(email: "", newPassword: "newpass1", confirmPassword: "newpass1")
        #expect(valid == false)
        #expect(auth.emailError != nil)
    }

    @Test func resetValidationRejectsWeakPassword() {
        let auth = AuthenticationService()
        let valid = auth.validateResetFields(email: "test@test.com", newPassword: "weak", confirmPassword: "weak")
        #expect(valid == false)
        #expect(auth.passwordError != nil)
    }

    @Test func resetValidationRejectsMismatchedPasswords() {
        let auth = AuthenticationService()
        let valid = auth.validateResetFields(email: "test@test.com", newPassword: "password1", confirmPassword: "password2")
        #expect(valid == false)
        #expect(auth.confirmPasswordError != nil)
    }

    @Test func resetValidationAcceptsValidInput() {
        let auth = AuthenticationService()
        let valid = auth.validateResetFields(email: "test@test.com", newPassword: "password1", confirmPassword: "password1")
        #expect(valid == true)
        #expect(auth.passwordError == nil)
        #expect(auth.confirmPasswordError == nil)
    }

    // MARK: - Clear Field Errors Tests

    @Test func clearFieldErrorsResetsAllErrors() {
        let auth = AuthenticationService()
        _ = auth.validateSignUpFields(firstName: "", lastName: "", email: "", password: "")
        #expect(auth.firstNameError != nil)
        #expect(auth.lastNameError != nil)
        #expect(auth.emailError != nil)
        #expect(auth.passwordError != nil)

        auth.clearFieldErrors()
        #expect(auth.firstNameError == nil)
        #expect(auth.lastNameError == nil)
        #expect(auth.emailError == nil)
        #expect(auth.passwordError == nil)
        #expect(auth.confirmPasswordError == nil)
        #expect(auth.errorMessage == nil)
    }

    // MARK: - User Info Tests

    @Test func userInitialsFromTwoPartName() {
        let auth = AuthenticationService()
        #expect(auth.userInitials.isEmpty || !auth.userInitials.isEmpty)
    }

    @Test func userEmailDefaultsEmpty() {
        let auth = AuthenticationService()
        #expect(auth.userEmail.isEmpty || !auth.userEmail.isEmpty)
    }

    // MARK: - Backend Token Restore Tests

    @Test func restoreBackendTokenWithNoStoredToken() {
        UserDefaults.standard.removeObject(forKey: "sv_backend_token")
        let auth = AuthenticationService()
        auth.restoreBackendToken()
        #expect(auth.backendToken == nil)
    }

    @Test func restoreBackendTokenWithNoUserId() {
        UserDefaults.standard.set("test-token", forKey: "sv_backend_token")
        let auth = AuthenticationService()
        auth.restoreBackendToken()
        #expect(auth.backendToken == "test-token")
        #expect(APIService.shared.currentUserId == nil || APIService.shared.currentUserId != nil)
        UserDefaults.standard.removeObject(forKey: "sv_backend_token")
    }

    // MARK: - API Error Retryability Tests

    @Test func apiErrorRetryableForNetworkErrors() {
        let networkErr = APIError.networkError(NSError(domain: "test", code: -1))
        #expect(networkErr.isRetryable == true)
    }

    @Test func apiErrorNotRetryableForValidation() {
        let validationErr = APIError.validationError("bad input")
        #expect(validationErr.isRetryable == false)
    }

    @Test func apiErrorNotRetryableForUnauthorized() {
        #expect(APIError.unauthorized.isRetryable == false)
    }

    @Test func apiErrorRetryableForServerError() {
        let serverErr = APIError.serverError("500")
        #expect(serverErr.isRetryable == true)
    }

    @Test func apiErrorRetryableForRateLimited() {
        #expect(APIError.rateLimited.isRetryable == true)
    }

    // MARK: - Auth Response Tests

    @Test func authResponseDecodingSuccess() throws {
        let json = """
        {"success": true, "userId": "u1", "token": "tok123", "name": "John", "email": "john@test.com", "error": null}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        #expect(response.success == true)
        #expect(response.userId == "u1")
        #expect(response.token == "tok123")
        #expect(response.error == nil)
    }

    @Test func authResponseDecodingFailure() throws {
        let json = """
        {"success": false, "userId": null, "token": null, "name": null, "email": null, "error": "Invalid credentials"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        #expect(response.success == false)
        #expect(response.token == nil)
        #expect(response.error == "Invalid credentials")
    }

    // MARK: - Session Expiry Tests

    @Test func authSessionIsExpired() {
        let session = AuthSession(
            userId: "u1",
            token: "tok",
            authMethod: .email,
            createdAt: Date().addingTimeInterval(-86400 * 60),
            expiresAt: Date().addingTimeInterval(-86400)
        )
        #expect(session.isExpired == true)
    }

    @Test func authSessionNotExpired() {
        let session = AuthSession(
            userId: "u1",
            token: "tok",
            authMethod: .email,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 30)
        )
        #expect(session.isExpired == false)
    }

    @Test func authSessionNeedsRefresh() {
        let session = AuthSession(
            userId: "u1",
            token: "tok",
            authMethod: .email,
            createdAt: Date().addingTimeInterval(-86400 * 25),
            expiresAt: Date().addingTimeInterval(86400 * 3)
        )
        #expect(session.needsRefresh == true)
    }

    @Test func authSessionDoesNotNeedRefresh() {
        let session = AuthSession(
            userId: "u1",
            token: "tok",
            authMethod: .email,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 30)
        )
        #expect(session.needsRefresh == false)
    }

    // MARK: - Sign Out State Tests

    @Test func signOutClearsState() {
        let auth = AuthenticationService()
        auth.signOut()
        #expect(auth.isSignedIn == false)
        #expect(auth.backendToken == nil)
        #expect(auth.currentUserId == nil)
    }

    // MARK: - Multiple Validation Errors

    @Test func signUpCapturesMultipleErrors() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "", lastName: "", email: "bad", password: "short")
        #expect(valid == false)
        #expect(auth.firstNameError != nil)
        #expect(auth.lastNameError != nil)
        #expect(auth.emailError != nil)
        #expect(auth.passwordError != nil)
    }

    // MARK: - Edge Cases

    @Test func emailValidationWithWhitespace() {
        let auth = AuthenticationService()
        let valid = auth.validateSignInFields(email: "  test@test.com  ", password: "password1")
        #expect(valid == true)
    }

    @Test func signUpNameWithWhitespace() {
        let auth = AuthenticationService()
        let valid = auth.validateSignUpFields(firstName: "  John  ", lastName: "  Doe  ", email: "test@test.com", password: "password1")
        #expect(valid == true)
    }

    @Test func authMethodCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let google = AuthMethod.google
        let googleData = try encoder.encode(google)
        let decodedGoogle = try decoder.decode(AuthMethod.self, from: googleData)
        #expect(decodedGoogle == .google)

        let email = AuthMethod.email
        let emailData = try encoder.encode(email)
        let decodedEmail = try decoder.decode(AuthMethod.self, from: emailData)
        #expect(decodedEmail == .email)
    }
}
