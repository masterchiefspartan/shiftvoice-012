import SwiftUI
import GoogleSignInSwift

struct SignInView: View {
    @Bindable var authService: AuthenticationService
    @State private var isSignUp: Bool = false
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @FocusState private var focusedField: SignInField?
    private let networkMonitor = NetworkMonitor.shared

    var body: some View {
        ZStack {
            SVTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    brandHeader
                        .padding(.bottom, 40)

                    emailForm
                        .padding(.horizontal, 24)

                    dividerRow
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)

                    googleButton
                        .padding(.horizontal, 24)

                    if !networkMonitor.isConnected {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 11))
                            Text("No internet connection")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(SVTheme.amber)
                        .padding(.top, 12)
                    }

                    Spacer().frame(height: 24)

                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(SVTheme.urgentRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if authService.passwordResetSuccess {
                        Text("Password reset successfully. Please sign in.")
                            .font(.footnote)
                            .foregroundStyle(SVTheme.successGreen)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer().frame(height: 32)

                    toggleModeButton

                    Spacer().frame(height: 24)

                    Text("Your data is secured and encrypted.\nOnly you and your team can access shift notes.")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 32)

                    Spacer().frame(height: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.easeOut(duration: 0.2), value: isSignUp)
        .animation(.easeOut(duration: 0.2), value: authService.errorMessage)
        .animation(.easeOut(duration: 0.2), value: authService.passwordResetSuccess)
        .sheet(isPresented: $authService.showPasswordReset) {
            PasswordResetView(authService: authService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(SVTheme.accent.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(SVTheme.accent)
            }

            VStack(spacing: 8) {
                Text("ShiftVoice")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(SVTheme.textPrimary)
                    .tracking(-0.5)
                Text(isSignUp ? "Create your account" : "Welcome back")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textSecondary)
            }
        }
    }

    private var emailForm: some View {
        VStack(spacing: 14) {
            if isSignUp {
                VStack(alignment: .leading, spacing: 4) {
                    fieldContainer(hasError: authService.nameError != nil) {
                        HStack(spacing: 12) {
                            Image(systemName: "person")
                                .font(.system(size: 16))
                                .foregroundStyle(SVTheme.textTertiary)
                                .frame(width: 20)
                            TextField("Full Name", text: $name)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .email }
                                .onChange(of: name) { _, _ in authService.nameError = nil }
                        }
                    }
                    if let error = authService.nameError {
                        fieldErrorLabel(error)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldContainer(hasError: authService.emailError != nil) {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope")
                            .font(.system(size: 16))
                            .foregroundStyle(SVTheme.textTertiary)
                            .frame(width: 20)
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .onChange(of: email) { _, _ in authService.emailError = nil }
                    }
                }
                if let error = authService.emailError {
                    fieldErrorLabel(error)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldContainer(hasError: authService.passwordError != nil) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock")
                            .font(.system(size: 16))
                            .foregroundStyle(SVTheme.textTertiary)
                            .frame(width: 20)
                        Group {
                            if isPasswordVisible {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(isSignUp ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submitForm() }

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .font(.system(size: 15))
                                .foregroundStyle(SVTheme.textTertiary)
                        }
                    }
                }
                if let error = authService.passwordError {
                    fieldErrorLabel(error)
                }
            }
            .onChange(of: password) { _, _ in authService.passwordError = nil }

            if !isSignUp {
                HStack {
                    Spacer()
                    Button {
                        authService.showPasswordReset = true
                        authService.clearFieldErrors()
                    } label: {
                        Text("Forgot Password?")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SVTheme.accent)
                    }
                }
                .padding(.top, -4)
            }

            Button {
                submitForm()
            } label: {
                HStack(spacing: 8) {
                    if authService.isSubmitting {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    }
                    Text(isSignUp ? "Create Account" : "Sign In")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(authService.isSubmitting ? SVTheme.accent.opacity(0.6) : SVTheme.accent)
                .clipShape(.rect(cornerRadius: 12))
            }
            .disabled(authService.isSubmitting)
            .padding(.top, 4)
        }
    }

    private func fieldContainer<Content: View>(hasError: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(SVTheme.surface)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(hasError ? SVTheme.urgentRed.opacity(0.6) : SVTheme.surfaceBorder, lineWidth: hasError ? 1.5 : 1)
            )
    }

    private func fieldErrorLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(SVTheme.urgentRed)
        .padding(.leading, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var dividerRow: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(SVTheme.divider)
                .frame(height: 1)
            Text("or")
                .font(.subheadline)
                .foregroundStyle(SVTheme.textTertiary)
            Rectangle()
                .fill(SVTheme.divider)
                .frame(height: 1)
        }
    }

    private var googleButton: some View {
        Button {
            authService.signInWithGoogle()
        } label: {
            HStack(spacing: 12) {
                googleLogo
                Text("Continue with Google")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SVTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(SVTheme.surface)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        }
    }

    private var toggleModeButton: some View {
        HStack(spacing: 4) {
            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                .font(.subheadline)
                .foregroundStyle(SVTheme.textSecondary)
            Button {
                withAnimation {
                    isSignUp.toggle()
                    clearFormOnModeSwitch()
                }
            } label: {
                Text(isSignUp ? "Sign In" : "Sign Up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.accent)
            }
        }
    }

    private var googleLogo: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
            Text("G")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 66/255, green: 133/255, blue: 244/255),
                            Color(red: 219/255, green: 68/255, blue: 55/255),
                            Color(red: 244/255, green: 180/255, blue: 0/255),
                            Color(red: 15/255, green: 157/255, blue: 88/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private func submitForm() {
        focusedField = nil
        authService.passwordResetSuccess = false
        if isSignUp {
            authService.signUpWithEmail(name: name, email: email, password: password)
        } else {
            authService.signInWithEmail(email: email, password: password)
        }
    }

    private func clearFormOnModeSwitch() {
        name = ""
        password = ""
        isPasswordVisible = false
        authService.clearFieldErrors()
        authService.passwordResetSuccess = false
    }
}

nonisolated enum SignInField: Hashable, Sendable {
    case name
    case email
    case password
}
