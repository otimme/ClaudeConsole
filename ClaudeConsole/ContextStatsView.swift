//
//  ContextStatsView.swift
//  ClaudeConsole
//
//  Display context usage statistics
//

import SwiftUI

struct ContextStatsView: View {
    @ObservedObject var contextMonitor: ContextMonitor

    var body: some View {
        HStack(spacing: 20) {
            // Overall context usage
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Context Usage")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: {
                        contextMonitor.requestContextUpdate()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh context stats")

                    Spacer()
                    Text("\(contextMonitor.contextStats.totalTokens.formatted()) / \(contextMonitor.contextStats.maxTokens.formatted())")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(width: 240)

                ProgressView(value: contextMonitor.contextStats.usedPercentage, total: 100)
                    .tint(colorForPercentage(contextMonitor.contextStats.usedPercentage))

                Text("\(Int(contextMonitor.contextStats.usedPercentage))% used")
                    .font(.caption2)
                    .foregroundColor(colorForPercentage(contextMonitor.contextStats.usedPercentage))
            }

            Divider()
                .frame(height: 40)

            // Breakdown
            HStack(spacing: 15) {
                StatPill(label: "System", value: contextMonitor.contextStats.systemPrompt + contextMonitor.contextStats.systemTools, color: .blue)
                StatPill(label: "Agents", value: contextMonitor.contextStats.customAgents, color: .purple)
                StatPill(label: "Messages", value: contextMonitor.contextStats.messages, color: .orange)
                StatPill(label: "Buffer", value: contextMonitor.contextStats.autocompactBuffer, color: .gray)
                StatPill(label: "Free", value: contextMonitor.contextStats.freeSpace, color: .green)
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

struct StatPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(formatTokens(value))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1000 {
            let k = Double(tokens) / 1000.0
            return String(format: "%.1fk", k)
        } else {
            return "\(tokens)"
        }
    }
}

#Preview {
    ContextStatsView(contextMonitor: ContextMonitor())
        .frame(width: 800)
}
