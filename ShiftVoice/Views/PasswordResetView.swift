import SwiftUI

struct PasswordResetView: View {
    let authService: AuthenticationService
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
                        fieldContainer {
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
                            }
                        }

                        fieldContainer {
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

                        fieldContainer {
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
                        Text("Reset Password")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(SVTheme.accent)
                            .clipShape(.rect(cornerRadius: 12))
                    }

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
                        authService.errorMessage = nil
                        dismiss()
                    }
                }
            }
        }
    }

    private func fieldContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(SVTheme.surface)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
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
