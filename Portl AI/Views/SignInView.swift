import SwiftUI

/// Simple sign-in screen — shows "Welcome to Portl" with Google/Apple login buttons.
/// The onboarding bubble experience is handled by OnboardingView before this screen.
struct SignInView: View {

    @State private var auth = AuthManager.shared
    @State private var emailInput = ""
    @State private var otpInput = ""
    @State private var showEmailFlow = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack {
                Spacer()

                if showEmailFlow {
                    emailFlowSection
                } else {
                    Text("Welcome to Portl")
                        .font(.appSemibold(size: 28))
                        .foregroundStyle(.primary)
                        .padding(.bottom, 40)

                    loginButtons
                }

                if let error = auth.authError {
                    Text(error)
                        .font(.publicaPlay(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 12)
                }

                Spacer()
                    .frame(height: 50)
            }
        }
    }

    // MARK: - Login Buttons

    private var loginButtons: some View {
        VStack(spacing: 16) {
            Button {
                Task { await auth.loginWithGoogle() }
            } label: {
                HStack(spacing: 12) {
                    Image("GoogleLogo")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)

                    Text("Continue with Google")
                        .font(.appSemibold(size: 16))
                        .foregroundStyle(Color.brandNavy)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.brandCream, in: Capsule())
            }
            .buttonStyle(.haptic)
            .padding(.horizontal, 24)

            Button {
                Task { await auth.loginWithApple() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.brandNavy)

                    Text("Continue with Apple")
                        .font(.appSemibold(size: 16))
                        .foregroundStyle(Color.brandNavy)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.brandCream, in: Capsule())
            }
            .buttonStyle(.haptic)
            .padding(.horizontal, 24)
        }
        .disabled(auth.isProcessing)
        .opacity(auth.isProcessing ? 0.6 : 1)
    }

    // MARK: - Email OTP Flow

    private var emailFlowSection: some View {
        VStack(spacing: 16) {
            if !auth.emailOTPSent {
                TextField("Email address", text: $emailInput)
                    .font(.publicaPlay(size: 16))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .background(.white, in: Capsule())
                    .padding(.horizontal, 40)

                Button {
                    Task { await auth.sendEmailCode(to: emailInput) }
                } label: {
                    Text(auth.isProcessing ? "Sending..." : "Send Code")
                        .font(.publicaPlay(size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.haptic)
                .background(Color.brandCream.opacity(0.2), in: Capsule())
                .padding(.horizontal, 40)
                .disabled(emailInput.isEmpty || auth.isProcessing)
            } else {
                Text("Enter the code sent to \(auth.emailForOTP)")
                    .font(.publicaPlay(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                TextField("Verification code", text: $otpInput)
                    .font(.publicaPlay(size: 20))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .background(.white, in: Capsule())
                    .padding(.horizontal, 40)

                Button {
                    Task { await auth.verifyEmailCode(otpInput) }
                } label: {
                    Text(auth.isProcessing ? "Verifying..." : "Verify")
                        .font(.publicaPlay(size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.haptic)
                .background(Color.brandCream.opacity(0.2), in: Capsule())
                .padding(.horizontal, 40)
                .disabled(otpInput.isEmpty || auth.isProcessing)
            }

            Button {
                withAnimation(.snappy(duration: 0.3)) {
                    showEmailFlow = false
                    auth.emailOTPSent = false
                    auth.authError = nil
                    otpInput = ""
                }
            } label: {
                Text("Back")
                    .font(.publicaPlay(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.haptic)
        }
    }
}

#Preview {
    SignInView()
}
