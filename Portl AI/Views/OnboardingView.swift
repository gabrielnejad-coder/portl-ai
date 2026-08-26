import SwiftUI

/// Interactive liquid glass bubble onboarding — first screen for new users.
/// Uses a [[stitchable]] Metal layer effect shader to create real refraction
/// of the underlying content (text, colors, blue band) through a glass sphere.
/// The user drags the bubble up to the top snap point to reveal login buttons.
struct OnboardingView: View {

    @State private var auth = AuthManager.shared

    // Email sign-in sheet
    @State private var showEmailSheet = false
    @State private var emailInput = ""
    @State private var otpInput = ""

    // Bubble position in points (converted to normalized 0–1 for shader)
    @State private var bubblePosition: CGPoint = .zero
    @State private var isDragging = false
    @State private var hasCompleted = false
    @State private var showLoginButtons = false
    @State private var showWelcomeText = false
    @State private var loginButtonsOpacity: CGFloat = 1.0

    // Glass radius in points — large sphere, animated to 0 on success
    @State private var glassRadius: CGFloat = 300

    // Frost & morph
    @State private var frostAmount: CGFloat = 0
    @State private var plusIconOpacity: CGFloat = 0

    // Hint pulse
    @State private var hintPulse = false

    // Swipe-up hint
    @State private var swipeHintOpacity: CGFloat = 1.0
    @State private var swipeHintYOffset: CGFloat = 0.0

    // Text transition during drag
    @State private var headlineOpacity: CGFloat = 1.0
    @State private var headlineYOffset: CGFloat = 0.0
    @State private var welcomeOpacity: CGFloat = 0.0
    @State private var welcomeY: CGFloat = 0.0  // set on appear

    // Drag tracking — finger offset so grab point stays under finger
    @State private var dragFingerOffset: CGFloat = 0
    @State private var dragFingerOffsetX: CGFloat = 0
    // Haptic buzzing — tracks progress at which last buzz fired
    @State private var lastBuzzProgress: CGFloat = 0
    // Persistent haptic generators — must be prepared ahead of time to actually fire
    private let buzzGenerator = UIImpactFeedbackGenerator(style: .medium)

    // Skip for returning users
    @AppStorage("hasCompletedOnboarding") private var hasOnboarded = false

    // Bubble sizing
    private let bubbleRadiusResting: CGFloat = 300  // large resting size at bottom
    private let creamBg = Color(red: 0.96, green: 0.96, blue: 0.96)

    var body: some View {
        if hasOnboarded {
            returningUserView
        } else {
            onboardingView
        }
    }

    // MARK: - Returning User View

    private var returningUserView: some View {
        ZStack {
            creamBg.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Text("Welcome to\nPortl.")
                    .font(.system(size: 34, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.brandNavy)

                Spacer()

                loginButtons

                Spacer()
                    .frame(height: 60)
            }
        }
    }

    // MARK: - Onboarding View

    private var onboardingView: some View {
        GeometryReader { geo in
            let screenW = geo.size.width
            let screenH = geo.size.height
            let textCenter = CGPoint(x: screenW / 2, y: screenH * 0.36)
            // Bubble center below screen edge — large arc peeks up from bottom
            // Use fixed resting radius so bottomSnap doesn't shift when glassRadius animates
            let bottomSnap = CGPoint(x: screenW / 2, y: screenH + bubbleRadiusResting * 0.3)
            let topSnap = CGPoint(x: screenW / 2, y: screenH * 0.32)

            // TimelineView drives the shimmer animation
            TimelineView(.animation) { timeline in
                let time: Double = timeline.date.timeIntervalSinceReferenceDate

                // All content in a single ZStack – the layer effect refracts everything
                ZStack {
                // Cream background
                creamBg.ignoresSafeArea()

                // Main headline text — fades out, drifts up slightly
                Text("Meet Your\nNew Wallet.")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black)
                    .opacity(headlineOpacity)
                    .position(x: textCenter.x, y: textCenter.y + headlineYOffset)

                // "Welcome to Portl." — frosted glass text with shimmer
                let welcomePhase = (time.truncatingRemainder(dividingBy: 3.0)) / 3.0
                let welcomeShimmerX = -0.3 + welcomePhase * 1.6

                Text("Welcome to\nPortl.")
                    .font(.system(size: 34, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black)
                    .overlay {
                        // Shimmer sweep layered on top
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.4),
                                .clear
                            ],
                            startPoint: UnitPoint(x: welcomeShimmerX - 0.2, y: 0.5),
                            endPoint: UnitPoint(x: welcomeShimmerX + 0.2, y: 0.5)
                        )
                        .mask {
                            Text("Welcome to\nPortl.")
                                .font(.system(size: 34, weight: .semibold))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .opacity(welcomeOpacity)
                    .position(x: textCenter.x, y: welcomeY)

                // Logo + Login buttons (after success)
                if showLoginButtons {
                    VStack(spacing: 24) {
                        loginButtons
                    }
                    .opacity(loginButtonsOpacity)
                    .transition(.opacity)
                    .position(x: screenW / 2, y: screenH - 100)
                }


            }
            // Apply the glass refraction shader — all values in points
            .layerEffect(
                ShaderLibrary.glassEffect(
                    .float2(screenW, screenH),
                    .float2(bubblePosition.x, bubblePosition.y),
                    .float(glassRadius),
                    .float(0.85),                    // refraction strength
                    .float(frostAmount)              // frost opacity (0 = clear, 1 = opaque cream)
                ),
                maxSampleOffset: CGSize(width: 350, height: 350)
            )

            // Portl symbol on top of the bubble — rendered after shader, not refracted
            .overlay {
                Image("PortlSymbol")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .opacity(plusIconOpacity)
                    .position(bubblePosition)
            }
            // "Swipe up to enter" hint with moving shimmer — always rendered, visibility via opacity
            .overlay {
                let hintY = screenH - bubbleRadiusResting * 0.7 + bubbleRadiusResting * 0.3 + 30
                // Derive shimmer phase from the continuously-updating time
                let phase = (time.truncatingRemainder(dividingBy: 3.0)) / 3.0
                let shimmerX = -0.3 + phase * 1.6  // sweeps from -0.3 to 1.3

                Text("Swipe up to enter")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.clear)
                    .overlay {
                        // Base grey + white shimmer sweep
                        ZStack {
                            Color(.systemGray3)
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.5),
                                    .clear
                                ],
                                startPoint: UnitPoint(x: shimmerX - 0.2, y: 0.5),
                                endPoint: UnitPoint(x: shimmerX + 0.2, y: 0.5)
                            )
                        }
                        .mask {
                            Text("Swipe up to enter")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    .position(x: screenW / 2, y: hintY + swipeHintYOffset)
                    .opacity(swipeHintOpacity)
            }
            // Invisible drag surface — covers screen above login buttons so gesture always works
            // When buttons are showing, only the top portion captures drags
            .overlay {
                VStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(height: showLoginButtons ? screenH - 200 : screenH)
                    if showLoginButtons {
                        Color.clear.frame(height: 200)
                            .allowsHitTesting(false)
                    }
                }
                .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    lastBuzzProgress = 0
                                    dragFingerOffset = value.startLocation.y - bubblePosition.y
                                    dragFingerOffsetX = value.startLocation.x - bubblePosition.x
                                    buzzGenerator.prepare()
                                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                }

                                // Map finger position directly to bubble position.
                                let fingerY = value.location.y
                                let fingerX = value.location.x
                                let targetBubbleY = fingerY - dragFingerOffset
                                let targetBubbleX = fingerX - dragFingerOffsetX

                                // X: allow horizontal movement but pull toward center
                                let centerX = screenW / 2
                                let dampedX = bubblePosition.x + (targetBubbleX - bubblePosition.x) * 0.25
                                // Soft spring toward center — stronger the further away
                                let xOffset = dampedX - centerX
                                let xCentered = centerX + xOffset * 0.85

                                // Dampen Y movement: blend between current and target for weighty feel
                                let dampedY = bubblePosition.y + (targetBubbleY - bubblePosition.y) * 0.25

                                // Clamp bottom: don't let the bubble go below its resting position
                                let clampedY = min(dampedY, bottomSnap.y)

                                // Rubber-band past topSnap — very soft, barely moves past
                                let rubberBandY: CGFloat
                                if clampedY < topSnap.y {
                                    let overshoot = topSnap.y - clampedY
                                    let dampened = 15.0 * log(1.0 + overshoot / 15.0)
                                    rubberBandY = topSnap.y - dampened
                                } else {
                                    rubberBandY = clampedY
                                }

                                // Set position immediately — no spring during drag
                                bubblePosition = CGPoint(x: xCentered, y: rubberBandY)

                                // Progress based on where the bubble IS between bottom and top
                                let totalRange = bottomSnap.y - topSnap.y
                                let distFromBottom = bottomSnap.y - rubberBandY
                                let rawProgress = min(max(distFromBottom / totalRange, 0.0), 1.0)

                                // Apply ease-in-out curve: faster near both ends, smoother in the middle
                                // Attempt a smoothstep-style curve: 3t² - 2t³
                                let linearProgress = rawProgress * rawProgress * (3.0 - 2.0 * rawProgress)

                                // Radius: shrinks from the start but slowly — cubic ease keeps it large early on
                                let morphedRadius: CGFloat = 42
                                let easedShrink = pow(rawProgress, 1.2)
                                let targetRadius = bubbleRadiusResting - (bubbleRadiusResting - morphedRadius) * easedShrink

                                // Frost: disabled — bubble stays clear glass
                                let frostProgress = max(rawProgress - 0.8, 0.0) / 0.2
                                let targetFrost: CGFloat = 0

                                // Buzzing kicks in at 30% — rapid medium impacts that get stronger
                                if rawProgress > 0.3 {
                                    let buzzZone = (rawProgress - 0.3) / 0.7  // 0→1 within buzz range
                                    // Tiny steps = tons of vibrations: 0.005 at 30% → 0.001 near top
                                    let step = 0.005 - buzzZone * 0.004
                                    if rawProgress - lastBuzzProgress >= step {
                                        lastBuzzProgress = rawProgress
                                        buzzGenerator.impactOccurred(intensity: 0.5 + buzzZone * 0.5)
                                        buzzGenerator.prepare()
                                    }
                                } else {
                                    lastBuzzProgress = 0
                                }

                                // Plus icon: fades in with frost
                                let targetPlus = frostProgress

                                // Swipe hint: fades out and drifts up over first 30% of travel
                                let hintFade = max(1.0 - rawProgress * 3.3, 0.0)
                                let hintDrift = -rawProgress * 40.0

                                // Headline: fades out over first 40% of travel
                                let headlineFade = max(1.0 - rawProgress * 2.5, 0.0)
                                let headlineDrift = -linearProgress * 30.0

                                // Welcome: starts fading in at 35% — right as headline finishes fading out
                                let welcomeRaw = max(rawProgress - 0.35, 0.0) / 0.65
                                let welcomeFade = min(welcomeRaw * 2.0, 1.0)
                                // Text rises from well below its final spot
                                let welcomeFinalY = screenH * 0.52  // center-ish of the screen
                                let easedDrift = 1.0 - pow(1.0 - min(welcomeRaw, 1.0), 2.0)
                                let welcomeCurrentY = welcomeFinalY + 220.0 * (1.0 - easedDrift)

                                // Fade login buttons/logo as bubble moves away from top
                                if showLoginButtons {
                                    // Fully visible at rawProgress 1.0, fully gone by 0.7
                                    loginButtonsOpacity = min(max((rawProgress - 0.7) / 0.3, 0.0), 1.0)
                                }

                                // Update all values immediately
                                glassRadius = targetRadius
                                frostAmount = targetFrost
                                plusIconOpacity = targetPlus
                                swipeHintOpacity = hintFade
                                swipeHintYOffset = hintDrift
                                headlineOpacity = headlineFade
                                headlineYOffset = headlineDrift
                                welcomeOpacity = welcomeFade
                                welcomeY = welcomeCurrentY
                            }
                            .onEnded { value in
                                let currentY = bubblePosition.y
                                let midThreshold = screenH * 0.72

                                // Clamp predicted velocity so fast flicks don't overshoot decisions
                                let clampedPrediction = max(min(value.predictedEndTranslation.height - value.translation.height, 150), -150)
                                let predictedY = currentY + clampedPrediction

                                if currentY < midThreshold || predictedY < midThreshold {
                                    snapToTop(topSnap: topSnap, screenW: screenW, screenH: screenH)
                                } else {
                                    snapToBottom(bottomSnap: bottomSnap, screenH: screenH)
                                }
                            }
                    )
            }
            .onAppear {
                bubblePosition = bottomSnap
                welcomeY = screenH * 0.52 + 220  // start 220pt below final position
            }
            } // TimelineView
        }
    }

    // MARK: - Snap Actions

    private func snapToBottom(bottomSnap: CGPoint, screenH: CGFloat) {
        isDragging = false
        withAnimation(.spring(response: 0.7, dampingFraction: 1.0)) {
            bubblePosition = bottomSnap
            glassRadius = bubbleRadiusResting
            frostAmount = 0
            plusIconOpacity = 0
            headlineOpacity = 1.0
            headlineYOffset = 0.0
            welcomeOpacity = 0.0
            welcomeY = screenH * 0.52 + 220
            loginButtonsOpacity = 0
        }
        // Swipe hint fades and drifts back down after the ball settles
        withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
            swipeHintOpacity = 1.0
            swipeHintYOffset = 0.0
        }
        // Remove login buttons after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            showLoginButtons = false
            hasCompleted = false
            loginButtonsOpacity = 1.0
        }
    }

    private func snapToTop(topSnap: CGPoint, screenW: CGFloat, screenH: CGFloat) {
        let morphedRadius: CGFloat = 42  // frosted pill size
        // Welcome text lands at center of screen
        let welcomeFinalY = screenH * 0.52

        withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) {
            bubblePosition = CGPoint(x: screenW / 2, y: topSnap.y)
            glassRadius = morphedRadius
            frostAmount = 0
            plusIconOpacity = 1.0
            swipeHintOpacity = 0
            headlineOpacity = 0
            headlineYOffset = -30
            welcomeOpacity = 1.0
            welcomeY = welcomeFinalY
        }

        // Logo + buttons fade in after morph settles
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            hasCompleted = true
            showLoginButtons = true
            loginButtonsOpacity = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isDragging = false
        }
    }

    // MARK: - Login Buttons

    private var loginButtons: some View {
        VStack(spacing: 12) {
            // Continue with Google
            Button {
                Task { await auth.loginWithGoogle() }
            } label: {
                HStack(spacing: 12) {
                    Image("GoogleLogo")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)

                    Text("Continue with Google")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.brandNavy)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
            }
            .buttonStyle(.haptic)
            .padding(.horizontal, 24)

            // Continue with Apple — coming soon
            Button {
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))

                    Text("Continue with Apple")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))

                    Text("Coming Soon")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.15), in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.brandNavy.opacity(0.5), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .disabled(true)
            .padding(.horizontal, 24)

            // Continue with Email — works everywhere OAuth can't (simulator included)
            Button {
                auth.authError = nil
                showEmailSheet = true
            } label: {
                Text("Continue with Email")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.brandNavy.opacity(0.7))
                    .frame(height: 40)
            }
            .buttonStyle(.haptic)

            if auth.isProcessing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Signing in...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            if let error = auth.authError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .disabled(auth.isProcessing)
        .opacity(auth.isProcessing ? 0.6 : 1)
        .sheet(isPresented: $showEmailSheet) {
            emailSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .onDisappear {
                    auth.emailOTPSent = false
                    auth.authError = nil
                    otpInput = ""
                }
        }
    }

    // MARK: - Email Sign-In Sheet

    private var emailSheet: some View {
        VStack(spacing: 16) {
            Text(auth.emailOTPSent ? "Check your email" : "Sign in with email")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 28)

            if !auth.emailOTPSent {
                TextField("Email address", text: $emailInput)
                    .font(.system(size: 16))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)

                Button {
                    Task { await auth.sendEmailCode(to: emailInput.trimmingCharacters(in: .whitespaces)) }
                } label: {
                    Text(auth.isProcessing ? "Sending..." : "Send Code")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.brandNavy, in: RoundedRectangle(cornerRadius: 26))
                }
                .buttonStyle(.haptic)
                .disabled(emailInput.trimmingCharacters(in: .whitespaces).isEmpty || auth.isProcessing)
                .padding(.horizontal, 24)
            } else {
                Text("We sent a code to \(auth.emailForOTP)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                TextField("6-digit code", text: $otpInput)
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)

                Button {
                    Task { await auth.verifyEmailCode(otpInput.trimmingCharacters(in: .whitespaces)) }
                } label: {
                    Text(auth.isProcessing ? "Verifying..." : "Verify")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.brandNavy, in: RoundedRectangle(cornerRadius: 26))
                }
                .buttonStyle(.haptic)
                .disabled(otpInput.trimmingCharacters(in: .whitespaces).isEmpty || auth.isProcessing)
                .padding(.horizontal, 24)

                Button("Use a different email") {
                    auth.emailOTPSent = false
                    otpInput = ""
                    auth.authError = nil
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            }

            if let error = auth.authError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
    }
}

#Preview {
    OnboardingView()
}
