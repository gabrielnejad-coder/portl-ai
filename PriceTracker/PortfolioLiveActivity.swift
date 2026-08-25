import WidgetKit
import SwiftUI
import ActivityKit

struct PortfolioLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PortfolioLiveActivityAttributes.self) { context in
            // Lock Screen / Banner presentation
            portfolioLockScreen(context: context)
                .activityBackgroundTint(.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded presentation
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Portfolio")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(context.state.formattedBalance)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("24h")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            Image(systemName: context.state.isPositive
                                  ? "arrowtriangle.up.fill"
                                  : "arrowtriangle.down.fill")
                                .font(.system(size: 8))
                            Text(context.state.formattedChange)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(context.state.isPositive ? .green : .red)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.formattedChangeAmount)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(context.state.isPositive ? .green : .red)
                        Spacer()
                        Text("Updated \(context.state.lastUpdated, style: .relative) ago")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Text("💰")
                    .font(.system(size: 14))
            } compactTrailing: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(context.state.isPositive ? .green : .red)
                        .frame(width: 6, height: 6)
                    Text(compactBalance(context.state.totalBalance))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            } minimal: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func portfolioLockScreen(context: ActivityViewContext<PortfolioLiveActivityAttributes>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Portfolio Balance")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(context.state.formattedBalance)
                    .font(.system(size: 24, weight: .medium))
                    .contentTransition(.numericText())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: context.state.isPositive
                          ? "arrowtriangle.up.fill"
                          : "arrowtriangle.down.fill")
                        .font(.system(size: 10))
                    Text(context.state.formattedChange)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(context.state.isPositive ? .green : .red)

                Text(context.state.formattedChangeAmount)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(context.state.isPositive ? .green : .red)
            }
        }
        .padding(16)
    }

    // MARK: - Helpers

    /// Compact balance for the Dynamic Island trailing slot
    private func compactBalance(_ value: Double) -> String {
        switch abs(value) {
        case 1_000_000...:
            return String(format: "$%.1fM", value / 1_000_000)
        case 1_000...:
            return String(format: "$%.1fK", value / 1_000)
        default:
            return String(format: "$%.0f", value)
        }
    }
}
