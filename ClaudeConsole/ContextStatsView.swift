//
//  ContextStatsView.swift
//  ClaudeConsole
//
//  Display context usage statistics - Fallout Pip-Boy style
//

import SwiftUI

struct ContextStatsView: View {
    @ObservedObject var contextMonitor: ContextMonitor

    var body: some View {
        HStack(spacing: 12) {
            // Context label with refresh
            HStack(spacing: 4) {
                Text("CTX")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.Fallout.tertiary)

                Button(action: {
                    contextMonitor.requestContextUpdate()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundColor(Color.Fallout.tertiary)
                }
                .buttonStyle(.plain)
                .help("Refresh context stats")
            }

            // Segmented progress bar
            HStack(spacing: 1) {
                ForEach(0..<15, id: \.self) { index in
                    let segmentThreshold = Double(index + 1) / 15.0 * 100
                    let isFilled = contextMonitor.contextStats.usedPercentage >= segmentThreshold

                    RoundedRectangle(cornerRadius: 1)
                        .fill(isFilled ? colorForPercentage(contextMonitor.contextStats.usedPercentage) : Color.Fallout.inactive)
                        .frame(width: 6, height: 10)
                }
            }

            // Percentage and token count
            Text("\(Int(contextMonitor.contextStats.usedPercentage))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(colorForPercentage(contextMonitor.contextStats.usedPercentage))

            Text("\(formatTokens(contextMonitor.contextStats.totalTokens))/\(formatTokens(contextMonitor.contextStats.maxTokens))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color.Fallout.tertiary)

            Rectangle()
                .fill(Color.Fallout.borderDim)
                .frame(width: 1, height: 30)

            // Compact breakdown
            HStack(spacing: 8) {
                CompactStatItem(label: "SYS", value: contextMonitor.contextStats.systemPrompt + contextMonitor.contextStats.systemTools + contextMonitor.contextStats.mcpTools)
                CompactStatItem(label: "MSG", value: contextMonitor.contextStats.messages)
                CompactStatItem(label: "FREE", value: contextMonitor.contextStats.freeSpace, highlight: true)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1000 {
            return String(format: "%.0fk", Double(tokens) / 1000.0)
        }
        return "\(tokens)"
    }

    private func colorForPercentage(_ percentage: Double) -> Color {
        if percentage >= 90 {
            return Color.Fallout.danger
        } else if percentage >= 70 {
            return Color.Fallout.warning
        } else {
            return Color.Fallout.primary
        }
    }
}

// Compact stat item for footer
struct CompactStatItem: View {
    let label: String
    let value: Int
    var highlight: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color.Fallout.tertiary)

            Text(formatTokens(value))
                .font(.system(size: 10, weight: highlight ? .medium : .regular, design: .monospaced))
                .foregroundColor(highlight ? Color.Fallout.primary : Color.Fallout.secondary)
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1000 {
            return String(format: "%.1fk", Double(tokens) / 1000.0)
        }
        return "\(tokens)"
    }
}

#Preview {
    ContextStatsView(contextMonitor: ContextMonitor())
        .frame(width: 800)
        .background(Color.Fallout.backgroundAlt)
}
