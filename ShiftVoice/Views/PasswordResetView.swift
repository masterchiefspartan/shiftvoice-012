import SwiftUI

struct PasswordResetView: View {
    @Bindable var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isNewPasswordVisible: Bool = false
    @FocusState private var focusedField: ResetField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 44))
                            .foregroundStyle(SVTheme.accent)

                        Text("Reset Password")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(SVTheme.textPrimary)

                        Text("Enter your email and choose a new password.")
                            .font(.subheadline)
                            .foregroundStyle(SVTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 14) {
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
                                        .onSubmit { focusedField = .newPassword }
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
                                        if isNewPasswordVisible {
                                            TextField("New Password", text: $newPassword)
                                        } else {
                                            SecureField("New Password", text: $newPassword)
                                        }
                                    }
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .newPassword)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .confirmPassword }

                                    Button {
                                        isNewPasswordVisible.toggle()
                                    } label: {
                                        Image(systemName: isNewPasswordVisible ? "eye.slash" : "eye")
                                            .font(.system(size: 15))
                                            .foregroundStyle(SVTheme.textTertiary)
                                    }
                                }
                            }
                            if let error = authService.passwordError {
                                fieldErrorLabel(error)
                            }
                        }
                        .onChange(of: newPassword) { _, _ in authService.passwordError = nil }

                        VStack(alignment: .leading, spacing: 4) {
                            fieldContainer(hasError: authService.confirmPasswordError != nil) {
                                HStack(spacing: 12) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(SVTheme.textTertiary)
                                        .frame(width: 20)
                                    SecureField("Confirm Password", text: $confirmPassword)
                                        .textContentType(.newPassword)
                                        .focused($focusedField, equals: .confirmPassword)
                                        .submitLabel(.go)
                                        .onSubmit { resetPassword() }
                                        .onChange(of: confirmPassword) { _, _ in authService.confirmPasswordError = nil }
                                }
                            }
                            if let error = authService.confirmPasswordError {
                                fieldErrorLabel(error)
                            }
                        }
                    }

                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(SVTheme.urgentRed)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        resetPassword()
                    } label: {
                        HStack(spacing: 8) {
                            if authService.isSubmitting {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text("Reset Password")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(authService.isSubmitting ? SVTheme.accent.opacity(0.6) : SVTheme.accent)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    .disabled(authService.isSubmitting)

                    Text("Must be at least 8 characters\nwith a letter and a number.")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        authService.clearFieldErrors()
                        dismiss()
                    }
                }
            }
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

    private func resetPassword() {
        focusedField = nil
        authService.resetPassword(email: email, newPassword: newPassword, confirmPassword: confirmPassword)
    }
}

nonisolated enum ResetField: Hashable, Sendable {
    case email
    case newPassword
    case confirmPassword
}
