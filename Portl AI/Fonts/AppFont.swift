import SwiftUI
import UIKit

// MARK: - Brand Colors (Atmosphere Blue)

extension Color {

    // MARK: Dark Mode Palette
    /// #060B14 — deep midnight base
    static let atmDarkBackground = Color(red: 0.024, green: 0.043, blue: 0.078)
    /// #101A2B — card/surface
    static let atmDarkSurface = Color(red: 0.063, green: 0.102, blue: 0.169)
    /// #13233A — elevated surface
    static let atmDarkElevated = Color(red: 0.075, green: 0.137, blue: 0.227)
    /// #2F80FF — primary accent
    static let atmPrimary = Color(red: 0.184, green: 0.502, blue: 1.0)
    /// #4A96FF — hover/secondary accent
    static let atmPrimaryHover = Color(red: 0.290, green: 0.588, blue: 1.0)
    /// #7CCBFF — glow / tertiary accent
    static let atmGlow = Color(red: 0.486, green: 0.796, blue: 1.0)
    /// #F4F8FF — primary text (dark mode)
    static let atmDarkText = Color(red: 0.957, green: 0.973, blue: 1.0)
    /// #B8C7DE — secondary text (dark mode)
    static let atmDarkTextSecondary = Color(red: 0.722, green: 0.780, blue: 0.871)
    /// #223654 — border (dark mode)
    static let atmDarkBorder = Color(red: 0.133, green: 0.212, blue: 0.329)

    // MARK: Light Mode Palette
    /// #F4F8FF — clean sky base
    static let atmLightBackground = Color(red: 0.957, green: 0.973, blue: 1.0)
    /// #FFFFFF — card/surface
    static let atmLightSurface = Color.white
    /// #F6FAFF — tinted surface
    static let atmLightTintedSurface = Color(red: 0.965, green: 0.980, blue: 1.0)
    /// #DCEBFF — soft primary tint
    static let atmSoftPrimary = Color(red: 0.863, green: 0.922, blue: 1.0)
    /// #9FE7FF — light accent
    static let atmLightAccent = Color(red: 0.624, green: 0.906, blue: 1.0)
    /// #0F1B2E — primary text (light mode)
    static let atmLightText = Color(red: 0.059, green: 0.106, blue: 0.180)
    /// #40526D — secondary text (light mode)
    static let atmLightTextSecondary = Color(red: 0.251, green: 0.322, blue: 0.427)
    /// #D6E3F5 — border (light mode)
    static let atmLightBorder = Color(red: 0.839, green: 0.890, blue: 0.961)

    // MARK: Legacy aliases (keep existing code working)
    static let brandCream = atmLightBackground
    static let brandNavy = atmDarkBackground
    static let brandWhite = Color.white
}

/// App-wide font helpers — uses SF Pro (system font) with weight variants
extension Font {
    /// Standard app font — system default, regular weight
    static func publicaPlay(size: CGFloat) -> Font {
        .system(size: size, weight: .regular)
    }

    /// Regular weight for prices and numerical data
    static func priceThin(size: CGFloat) -> Font {
        .system(size: size, weight: .regular)
    }

    /// Medium weight for section headers and emphasis
    static func appMedium(size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    /// Semibold for important labels
    static func appSemibold(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

/// Phantom-wallet-inspired button style — 0.96 scale press with light haptic and spring-back
struct HapticButtonStyle: ButtonStyle {
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    feedback.impactOccurred()
                }
            }
    }
}

extension ButtonStyle where Self == HapticButtonStyle {
    static var haptic: HapticButtonStyle { HapticButtonStyle() }
    /// Alias for the Phantom-style press animation
    static var phantom: HapticButtonStyle { HapticButtonStyle() }
}

/// A button style for news cards — lifts on press with shadow elevation and light haptic
struct ElevatingButtonStyle: ButtonStyle {
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .shadow(
                color: .primary.opacity(configuration.isPressed ? 0.06 : 0),
                radius: configuration.isPressed ? 12 : 0,
                y: configuration.isPressed ? 4 : 0
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    feedback.impactOccurred()
                }
            }
    }
}

extension ButtonStyle where Self == ElevatingButtonStyle {
    static var elevating: ElevatingButtonStyle { ElevatingButtonStyle() }
}

// MARK: - Phantom Animation Constants

/// Shared animation curves used throughout the app — Phantom wallet inspired.
/// Rule: never use .linear. Always spring or easeInOut with weight and momentum.
enum PhantomAnimation {
    /// Staggered row entrance — fade up with spring
    static func rowEntrance(index: Int) -> Animation {
        .spring(response: 0.4, dampingFraction: 0.8)
        .delay(Double(index) * 0.04)
    }

    /// Card appearance — scale from 0.97 with spring
    static let cardAppear: Animation = .spring(response: 0.5, dampingFraction: 0.85)

    /// Tab crossfade
    static let tabSwitch: Animation = .easeInOut(duration: 0.2)

    /// Chart line draw
    static let chartDraw: Animation = .easeInOut(duration: 0.6)

    /// Balance counter tick duration
    static let balanceCountDuration: Double = 0.8

    /// Navigation push — slide + fade
    static let navPush: Animation = .spring(response: 0.3, dampingFraction: 0.85)
}

/// Displays a price with dimmed decimals: "$282" white, ".35" dimmer
struct PriceText: View {
    let amount: Double
    var size: CGFloat = 15

    var body: some View {
        let formatted = formatPrice(amount)
        HStack(spacing: 0) {
            Text(formatted.whole)
                .font(.publicaPlay(size: size))
                .foregroundStyle(.primary)
            Text(formatted.decimal)
                .font(.publicaPlay(size: size))
                .foregroundStyle(.secondary)
        }
    }

    private func formatPrice(_ value: Double) -> (whole: String, decimal: String) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","

        // Dynamic precision: show more decimals for smaller prices
        let decimals = Self.decimalPlaces(for: value)
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals

        let str = formatter.string(from: NSNumber(value: value)) ?? "0.00"

        if let dotIndex = str.firstIndex(of: ".") {
            let whole = "$" + str[str.startIndex..<dotIndex]
            let decimal = String(str[dotIndex...])
            return (String(whole), decimal)
        }
        return ("$" + str, "")
    }

    /// Returns the appropriate number of decimal places based on price magnitude.
    /// Large prices get 2 decimals, tiny prices get up to 8 to show meaningful digits.
    static func decimalPlaces(for value: Double) -> Int {
        let abs = Swift.abs(value)
        switch abs {
        case 1...:          return 2   // $1.00+      → 2 decimals
        case 0.01..<1:      return 4   // $0.0412     → 4 decimals
        case 0.0001..<0.01: return 6   // $0.004123   → 6 decimals
        default:            return 8   // $0.00000412 → 8 decimals
        }
    }
}
