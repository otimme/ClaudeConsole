//
//  StatsView.swift
//  ClaudeConsole
//
//  Statistics display views
//

import SwiftUI

struct TopStatsView: View {
    @ObservedObject var statsMonitor: ClaudeStatsMonitor

    var body: some View {
        HStack(spacing: 20) {
            StatItem(label: "Tokens", value: "\(statsMonitor.stats.totalTokens.formatted())")
            StatItem(label: "Input", value: "\(statsMonitor.stats.inputTokens.formatted())")
            StatItem(label: "Output", value: "\(statsMonitor.stats.outputTokens.formatted())")
            StatItem(label: "Cache Read", value: "\(statsMonitor.stats.cacheReadTokens.formatted())")

            Spacer()

            StatItem(label: "Cost", value: statsMonitor.stats.formattedCost)
            StatItem(label: "Duration", value: statsMonitor.stats.formattedDuration)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct BottomStatsView: View {
    @ObservedObject var statsMonitor: ClaudeStatsMonitor

    var body: some View {
        HStack(spacing: 20) {
            StatItem(label: "Lines Added", value: "+\(statsMonitor.stats.linesAdded)", color: .green)
            StatItem(label: "Lines Removed", value: "-\(statsMonitor.stats.linesRemoved)", color: .red)

            Spacer()

            Text("Claude Code Session Stats")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct StatItem: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

#Preview {
    VStack {
        TopStatsView(statsMonitor: ClaudeStatsMonitor())
        Spacer()
        BottomStatsView(statsMonitor: ClaudeStatsMonitor())
    }
}
