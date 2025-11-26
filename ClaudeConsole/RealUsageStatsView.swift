//
//  RealUsageStatsView.swift
//  ClaudeConsole
//
//  Display real usage limits from /usage command
//

import SwiftUI

struct RealUsageStatsView: View {
    @ObservedObject var usageMonitor: UsageMonitor

    var body: some View {
        HStack(spacing: 30) {
            // Status Indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.leading, 4)

            // Current Session (Daily)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Current Session")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(usageMonitor.usageStats.dailyTokensUsed)%")
                        .font(.caption)
                        .foregroundColor(colorForPercentage(Double(usageMonitor.usageStats.dailyTokensUsed)))
                }
                .frame(width: 150)

                ProgressView(value: Double(usageMonitor.usageStats.dailyTokensUsed), total: 100)
                    .tint(colorForPercentage(Double(usageMonitor.usageStats.dailyTokensUsed)))

                Text("Resets daily")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 30)

            // Weekly Usage (All Models)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Weekly (All Models)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(usageMonitor.usageStats.weeklyTokensUsed)%")
                        .font(.caption)
                        .foregroundColor(colorForPercentage(Double(usageMonitor.usageStats.weeklyTokensUsed)))
                }
                .frame(width: 150)

                ProgressView(value: Double(usageMonitor.usageStats.weeklyTokensUsed), total: 100)
                    .tint(colorForPercentage(Double(usageMonitor.usageStats.weeklyTokensUsed)))

                Text("Resets weekly")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 30)

            // Weekly Sonnet Usage
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Weekly (Sonnet)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(usageMonitor.usageStats.sonnetTokensUsed)%")
                        .font(.caption)
                        .foregroundColor(colorForPercentage(Double(usageMonitor.usageStats.sonnetTokensUsed)))
                }
                .frame(width: 150)

                ProgressView(value: Double(usageMonitor.usageStats.sonnetTokensUsed), total: 100)
                    .tint(colorForPercentage(Double(usageMonitor.usageStats.sonnetTokensUsed)))

                Text("Sonnet only")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func colorForPercentage(_ percentage: Double) -> Color {
        if percentage >= 90 {
            return .red
        } else if percentage >= 70 {
            return .orange
        } else {
            return .green
        }
    }

    private var statusColor: Color {
        switch usageMonitor.fetchStatus {
        case .idle:
            return .gray
        case .fetching:
            return .green
        case .success:
            return .green
        case .failed:
            return .red
        }
    }
}

#Preview {
    RealUsageStatsView(usageMonitor: UsageMonitor())
        .frame(width: 700)
}
