//
//  UsageStatsView.swift
//  ClaudeConsole
//
//  Display usage limits and quotas
//

import SwiftUI

struct UsageStatsView: View {
    @ObservedObject var usageMonitor: JSONLUsageMonitor

    var body: some View {
        HStack(spacing: 30) {
            // Current Session
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Session")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(usageMonitor.currentSessionUsage.totalTokens.formatted()) tokens")
                    .font(.system(.body, design: .monospaced))
            }

            Divider()
                .frame(height: 30)

            // Daily Usage
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Daily Usage (est.)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", usageMonitor.dailyPercentage))
                        .font(.caption)
                        .foregroundColor(colorForPercentage(usageMonitor.dailyPercentage))
                }
                .frame(width: 180)

                ProgressView(value: usageMonitor.dailyPercentage, total: 100)
                    .tint(colorForPercentage(usageMonitor.dailyPercentage))

                Text("\(usageMonitor.currentSessionUsage.totalTokens.formatted()) tokens")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 30)

            // Weekly Usage
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Weekly Usage (est.)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", usageMonitor.weeklyPercentage))
                        .font(.caption)
                        .foregroundColor(colorForPercentage(usageMonitor.weeklyPercentage))
                }
                .frame(width: 180)

                ProgressView(value: usageMonitor.weeklyPercentage, total: 100)
                    .tint(colorForPercentage(usageMonitor.weeklyPercentage))

                Text("\(usageMonitor.currentSessionUsage.totalTokens.formatted()) tokens")
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
}

#Preview {
    UsageStatsView(usageMonitor: JSONLUsageMonitor())
        .frame(width: 600)
}
