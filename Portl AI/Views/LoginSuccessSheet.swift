import SwiftUI

/// Success sheet shown after login — slides up from the bottom with a checkmark animation
struct LoginSuccessSheet: View {

    var onDone: () -> Void

    @State private var checkScale: CGFloat = 0
    @State private var checkOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var particlePhase: CGFloat = 0
    @State private var glowPulse: Double = 0.4

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(.primary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            Spacer()

            // Checkmark animation area
            ZStack {
                // Very subtle green glow behind checkmark
                Circle()
                    .fill(Color.green.opacity(glowPulse * 0.15))
                    .frame(width: 140, height: 140)
                    .blur(radius: 30)
                    .opacity(ringOpacity)

                // Orbiting particles
                ForEach(0..<8, id: \.self) { i in
                    Circle()
                        .fill(Color.green.opacity(Double.random(in: 0.3...0.7)))
                        .frame(width: CGFloat.random(in: 4...8))
                        .offset(
                            x: cos(CGFloat(i) * .pi / 4 + particlePhase) * 60,
                            y: sin(CGFloat(i) * .pi / 4 + particlePhase) * 60
                        )
                        .opacity(ringOpacity * 0.6)
                }

                // Green ring
                Circle()
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: 80, height: 80)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)

                // Checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.green)
                    .scaleEffect(checkScale)
                    .opacity(checkOpacity)
            }
            .frame(height: 160)

            // Success text
            Text("Successfully")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
                .opacity(textOpacity)
                .padding(.top, 8)

            Text("You have successfully signed in\nto your account.")
                .font(.publicaPlay(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(textOpacity)
                .padding(.top, 12)

            Spacer()

            // Done button — liquid glass
            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.appSemibold(size: 17))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .glassEffect(in: .capsule)
            }
            .buttonStyle(.haptic)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .opacity(buttonOpacity)
        }
        .task {
            // Staggered animations
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) {
                ringScale = 1
                ringOpacity = 1
            }

            try? await Task.sleep(for: .milliseconds(200))

            withAnimation(.spring(duration: 0.4, bounce: 0.5)) {
                checkScale = 1
                checkOpacity = 1
            }

            // Trigger haptic
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)

            try? await Task.sleep(for: .milliseconds(200))

            withAnimation(.easeOut(duration: 0.4)) {
                textOpacity = 1
            }

            try? await Task.sleep(for: .milliseconds(150))

            withAnimation(.easeOut(duration: 0.3)) {
                buttonOpacity = 1
            }

            // Start particle orbit and glow pulse
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: false)) {
                particlePhase = .pi * 2
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowPulse = 1.0
            }
        }
    }
}

#Preview {
    LoginSuccessSheet(onDone: {})
        .preferredColorScheme(.light)
}
