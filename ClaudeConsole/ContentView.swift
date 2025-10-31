//
//  ContentView.swift
//  ClaudeConsole
//
//  Created by Olaf Timme on 31/10/2025.
//

import SwiftUI
import SwiftTerm

struct ContentView: View {
    @StateObject private var usageMonitor = UsageMonitor()
    @StateObject private var contextMonitor = ContextMonitor()
    @State private var terminalController: LocalProcessTerminalView?

    var body: some View {
        VStack(spacing: 0) {
            // Real usage stats from /usage command
            RealUsageStatsView(usageMonitor: usageMonitor)
                .frame(height: 70)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Terminal in the middle
            TerminalView(terminalController: $terminalController)
                .frame(minWidth: 800, minHeight: 400)

            Divider()

            // Context usage statistics
            ContextStatsView(contextMonitor: contextMonitor)
                .frame(height: 60)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
