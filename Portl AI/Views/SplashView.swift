import SwiftUI

/// Animated splash screen that displays the PORTL logo on launch
struct SplashView: View {

    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0

    var onFinished: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            Image("PortlLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
        }
        .task {
            withAnimation(.easeOut(duration: 0.5)) {
                logoOpacity = 1
                logoScale = 1
            }

            try? await Task.sleep(for: .milliseconds(1500))
            onFinished()
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
