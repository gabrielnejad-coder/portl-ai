import SwiftUI

/// Interstitial "Thinking" screen shown after successful login.
/// White background, shimmer text, drifting aurora, rising particles,
/// then a glass bubble card pops up from the center.
struct ThinkingView: View {

    var onFinished: () -> Void

    // MARK: - Animation state
    @State private var textOpacity: Double = 0
    @State private var particles: [Particle] = []
    @State private var particlesVisible = false

    // Aurora background
    @State private var auroraOpacity: Double = 0
    @State private var auroraPhase1: CGFloat = 0
    @State private var auroraPhase2: CGFloat = 0
    @State private var auroraPhase3: CGFloat = 0

    // Text fade gradient drift
    @State private var fadeGradientOffset: CGFloat = 0

    // Bubble card
    @State private var bubbleYOffset: CGFloat = 30
    @State private var bubbleOpacity: Double = 0

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat        // 0–1 normalized
        var startY: CGFloat   // starting Y (bottom area)
        var size: CGFloat
        var opacity: Double
        var speed: CGFloat    // points per second conceptually
        var drift: CGFloat    // horizontal sway amplitude
        var delay: Double     // stagger start
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                Color.white.ignoresSafeArea()

                // ── Aurora color blobs — anchored to bottom corners ──
                ZStack {
                    // Bottom-left corner: soft blue
                    Ellipse()
                        .fill(Color(red: 0.5, green: 0.7, blue: 0.95).opacity(0.7))
                        .frame(width: 450, height: 400)
                        .blur(radius: 80)
                        .position(x: -30 + auroraPhase1 * 35, y: h + 40 + auroraPhase2 * -50)

                    // Bottom-right corner: lavender/purple
                    Ellipse()
                        .fill(Color(red: 0.72, green: 0.62, blue: 0.87).opacity(0.6))
                        .frame(width: 430, height: 370)
                        .blur(radius: 75)
                        .position(x: w + 30 + auroraPhase2 * -30, y: h + 30 + auroraPhase3 * -45)

                    // Left edge: cool blue creeping up
                    Ellipse()
                        .fill(Color(red: 0.6, green: 0.72, blue: 0.86).opacity(0.45))
                        .frame(width: 300, height: 450)
                        .blur(radius: 85)
                        .position(x: -50 + auroraPhase3 * 25, y: h * 0.62 + auroraPhase1 * -35)
                }
                .opacity(auroraOpacity)
                .ignoresSafeArea()

                // ── Rising particles ──
                ForEach(particles) { p in
                    Circle()
                        .fill(Color.black.opacity(p.opacity))
                        .frame(width: p.size, height: p.size)
                        .modifier(RisingParticleModifier(
                            particle: p,
                            screenWidth: w,
                            screenHeight: h,
                            isAnimating: particlesVisible
                        ))
                }

                // ── "Thinking" text with shimmer ──
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (time.truncatingRemainder(dividingBy: 3.0)) / 3.0
                    let shimmerX = -0.3 + phase * 1.6

                    Text("Thinking")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.clear)
                        .overlay {
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
                                Text("Thinking")
                                    .font(.system(size: 32, weight: .semibold))
                            }
                        }
                        .mask {
                            LinearGradient(
                                colors: [.white, .white, .white.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .scaleEffect(y: 1.6)
                            .offset(y: fadeGradientOffset)
                        }
                }
                .opacity(textOpacity)
                .position(x: w / 2, y: h * 0.45)

                // ── Glass cards layout ──
                let mainW = max(w - 72, 1)
                let mainH = max(h * 0.52, 1)
                let smallW = max(mainW * 0.46, 1)
                let smallH = max(smallW * 0.62, 1)

                ZStack {
                    // Main large card — shifted left to make room for small card
                    ZStack(alignment: .top) {
                        Color.clear
                            .frame(width: mainW, height: mainH)
                            .glassEffect(.regular.tint(.white), in: .rect(cornerRadius: 44))

                        // Warm green/amber gradient overlay on top half
                        LinearGradient(
                            colors: [
                                Color(red: 0.78, green: 0.80, blue: 0.55).opacity(0.5),
                                Color(red: 0.82, green: 0.78, blue: 0.58).opacity(0.35),
                                Color(red: 0.85, green: 0.82, blue: 0.65).opacity(0.15),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                        .frame(width: mainW, height: mainH)
                        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                        .allowsHitTesting(false)
                    }
                    .offset(x: -14)

                    // Small companion card — right edge, vertically centered-upper
                    Color.clear
                        .frame(width: smallW, height: smallH)
                        .glassEffect(.regular.tint(.white), in: .rect(cornerRadius: 24))
                        .offset(x: mainW * 0.30, y: -mainH * 0.05)
                }
                .offset(y: bubbleYOffset)
                .opacity(bubbleOpacity)
                .position(x: w / 2, y: h * 0.40)
            }
            .task {
                // Seed particles
                seedParticles(screenWidth: w, screenHeight: h)

                // Fade in text
                withAnimation(.easeOut(duration: 0.8)) {
                    textOpacity = 1
                }

                // Text fade gradient drifts up and down
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    fadeGradientOffset = 12
                }

                // Aurora fades in slowly
                withAnimation(.easeOut(duration: 2.0)) {
                    auroraOpacity = 1
                }

                // Aurora waving — each blob drifts on its own cycle
                withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                    auroraPhase1 = 1
                }
                withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                    auroraPhase2 = 1
                }
                withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                    auroraPhase3 = 1
                }

                // Start particles
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.linear(duration: 0.1)) {
                    particlesVisible = true
                }

                // After 4 seconds — pop the bubble card
                try? await Task.sleep(for: .seconds(4))

                // Fade out thinking text immediately
                withAnimation(.easeOut(duration: 0.25)) {
                    textOpacity = 0
                }

                // Fade in the card with a quick upward drift
                withAnimation(.easeOut(duration: 0.4)) {
                    bubbleYOffset = 0
                    bubbleOpacity = 1
                }

                // Hold for a beat, then dismiss
                try? await Task.sleep(for: .seconds(1.2))
                onFinished()
            }
        }
    }

    private func seedParticles(screenWidth: CGFloat, screenHeight: CGFloat) {
        particles = (0..<20).map { _ in
            Particle(
                x: CGFloat.random(in: 0.1...0.9),
                startY: CGFloat.random(in: 0.7...1.1),
                size: CGFloat.random(in: 2...5),
                opacity: Double.random(in: 0.08...0.25),
                speed: CGFloat.random(in: 30...70),
                drift: CGFloat.random(in: 10...30),
                delay: Double.random(in: 0...2)
            )
        }
    }
}

/// Animates a single particle rising from bottom to top with gentle horizontal sway.
struct RisingParticleModifier: ViewModifier, Animatable {

    let particle: ThinkingView.Particle
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let isAnimating: Bool

    func body(content: Content) -> some View {
        content
            .modifier(RisingParticlePositionEffect(
                particle: particle,
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                isAnimating: isAnimating
            ))
    }
}

/// Uses TimelineView for smooth per-frame particle positioning.
struct RisingParticlePositionEffect: ViewModifier {

    let particle: ThinkingView.Particle
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let isAnimating: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let elapsed = isAnimating
                ? max(0, timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 20))
                : 0
            let adjustedTime = max(0, elapsed - particle.delay)

            // Rise from bottom
            let travelDistance = particle.speed * CGFloat(adjustedTime)
            let baseY = screenHeight * particle.startY - travelDistance
            // Wrap around when off-screen
            let range = screenHeight * 1.3
            let wrappedY = baseY < -20
                ? screenHeight + ((baseY + 20).truncatingRemainder(dividingBy: range))
                : baseY

            // Gentle horizontal sway
            let sway = sin(CGFloat(adjustedTime) * 0.8 + particle.x * 10) * particle.drift
            let posX = screenWidth * particle.x + sway

            content
                .position(x: posX, y: wrappedY)
                .opacity(adjustedTime > 0 ? particle.opacity : 0)
        }
    }
}

#Preview {
    ThinkingView(onFinished: {})
}
