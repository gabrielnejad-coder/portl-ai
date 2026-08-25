import WidgetKit
import SwiftUI
import ActivityKit

struct CryptoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CryptoLiveActivityAttributes.self) { context in
            // Lock Screen / Banner presentation
            lockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded presentation
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.symbol.uppercased())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.formattedPrice)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        HStack(spacing: 2) {
                            Image(systemName: context.state.isPositive
                                  ? "arrowtriangle.up.fill"
                                  : "arrowtriangle.down.fill")
                                .font(.system(size: 8))
                            Text(context.state.formattedChange)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(context.state.isPositive ? .green : .red)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.name)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("24h Low")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(formatPrice(context.state.low24h))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("24h High")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(formatPrice(context.state.high24h))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.top, 4)

                    Link(destination: URL(string: "portlai://stop-tracking")!) {
                        Text("Stop Tracking")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                }
            } compactLeading: {
                Text(context.attributes.symbol.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } compactTrailing: {
                HStack(spacing: 2) {
                    Circle()
                        .fill(context.state.isPositive ? .green : .red)
                        .frame(width: 6, height: 6)
                    Text(context.state.formattedPrice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            } minimal: {
                Text(context.attributes.symbol.prefix(2).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<CryptoLiveActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(context.attributes.symbol.uppercased())
                            .font(.system(size: 18, weight: .bold))
                        Text(context.attributes.name)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Text(context.state.formattedPrice)
                        .font(.system(size: 28, weight: .medium))
                        .contentTransition(.numericText())
                }

                Spacer()

                VStack(spacing: 2) {
                    Image(systemName: context.state.isPositive
                          ? "arrowtriangle.up.fill"
                          : "arrowtriangle.down.fill")
                        .font(.system(size: 12))
                    Text(context.state.formattedChange)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(context.state.isPositive ? .green : .red)
            }

            HStack {
                HStack(spacing: 4) {
                    Text("L:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(formatPrice(context.state.low24h))
                        .font(.system(size: 12, weight: .medium))
                }

                Spacer()

                GeometryReader { geo in
                    let range = context.state.high24h - context.state.low24h
                    let position = range > 0
                        ? (context.state.currentPrice - context.state.low24h) / range
                        : 0.5
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.gray.opacity(0.3))
                            .frame(height: 4)
                        Circle()
                            .fill(context.state.isPositive ? .green : .red)
                            .frame(width: 8, height: 8)
                            .offset(x: max(0, min(geo.size.width - 8,
                                                   geo.size.width * position)))
                    }
                }
                .frame(height: 8)

                HStack(spacing: 4) {
                    Text("H:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(formatPrice(context.state.high24h))
                        .font(.system(size: 12, weight: .medium))
                }
            }

            HStack {
                Text("Updated \(context.state.lastUpdated, style: .relative) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: URL(string: "portlai://stop-tracking")!) {
                    Text("Stop Tracking")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func formatPrice(_ value: Double) -> String {
        let decimals: Int
        let abs = Swift.abs(value)
        switch abs {
        case 1...:          decimals = 2
        case 0.01..<1:      decimals = 4
        case 0.0001..<0.01: decimals = 6
        default:            decimals = 8
        }
        return String(format: "$%.\(decimals)f", value)
    }
}
