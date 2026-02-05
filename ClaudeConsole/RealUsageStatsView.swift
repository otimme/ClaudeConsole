//
//  RealUsageStatsView.swift
//  ClaudeConsole
//
//  Display real usage limits from /usage command - Fallout Pip-Boy style
//

import SwiftUI

struct RealUsageStatsView: View {
    @ObservedObject var usageMonitor: UsageMonitor

    var body: some View {
        HStack(spacing: 16) {
            // Status Indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.8), radius: 2)

                Text(statusText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.Fallout.tertiary)
            }
            .frame(width: 40)

            // Current Session (Daily)
            CompactUsageStatPanel(
                title: "SESSION",
                percentage: usageMonitor.usageStats.dailyTokensUsed
            )

            Rectangle()
                .fill(Color.Fallout.borderDim)
                .frame(width: 1, height: 30)

            // Weekly Usage (All Models)
            CompactUsageStatPanel(
                title: "WEEKLY",
                percentage: usageMonitor.usageStats.weeklyTokensUsed
            )

            Rectangle()
                .fill(Color.Fallout.borderDim)
                .frame(width: 1, height: 30)

            // Weekly model-specific usage (Opus/Sonnet/Haiku)
            CompactUsageStatPanel(
                title: usageMonitor.modelTier.isEmpty ? "MODEL" : usageMonitor.modelTier.uppercased(),
                percentage: usageMonitor.usageStats.sonnetTokensUsed
            )

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch usageMonitor.fetchStatus {
        case .idle:
            return Color.Fallout.tertiary
        case .fetching:
            return Color.Fallout.primary
        case .success:
            return Color.Fallout.primary
        case .failed:
            return Color.Fallout.danger
        }
    }

    private var statusText: String {
        switch usageMonitor.fetchStatus {
        case .idle:
            return "IDLE"
        case .fetching:
            return "SYNC"
        case .success:
            return "LIVE"
        case .failed:
            return "ERR"
        }
    }
}

// Compact usage stat panel with Fallout styling
struct CompactUsageStatPanel: View {
    let title: String
    let percentage: Int

    private var fillColor: Color {
        if percentage >= 90 {
            return Color.Fallout.danger
        } else if percentage >= 70 {
            return Color.Fallout.warning
        } else {
            return Color.Fallout.primary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Title
            Text(title)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color.Fallout.tertiary)

            // Segmented progress bar
            HStack(spacing: 1) {
                ForEach(0..<10, id: \.self) { index in
                    let segmentThreshold = Double(index + 1) / 10.0 * 100
                    let isFilled = Double(percentage) >= segmentThreshold

                    RoundedRectangle(cornerRadius: 1)
                        .fill(isFilled ? fillColor : Color.Fallout.inactive)
                        .frame(width: 8, height: 10)
                }
            }

            // Percentage
            Text("\(percentage)%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(fillColor)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

#Preview {
    RealUsageStatsView(usageMonitor: UsageMonitor())
        .frame(width: 700)
        .background(Color.Fallout.backgroundAlt)
}
