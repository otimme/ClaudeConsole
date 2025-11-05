//
//  RadialMenuProfileSelector.swift
//  ClaudeConsole
//
//  Created by Claude Code
//

import SwiftUI

struct RadialMenuProfileSelector: View {
    @ObservedObject var profileManager: RadialMenuProfileManager
    @State private var showProfileEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Radial Menu Profile")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                // Profile dropdown
                Picker("", selection: Binding(
                    get: { profileManager.activeProfile },
                    set: { profileManager.selectProfile($0) }
                )) {
                    ForEach(profileManager.profiles) { profile in
                        Text(profile.name).tag(profile)
                    }
                }
                .labelsHidden()
                .frame(width: 200)

                // Config button
                Button(action: { showProfileEditor.toggle() }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Configure profiles")
            }

            // Show menu assignments
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("L1")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(profileManager.activeProfile.l1Menu.name)
                        .font(.caption)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("R1")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(profileManager.activeProfile.r1Menu.name)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(SwiftUI.Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .sheet(isPresented: $showProfileEditor) {
            RadialMenuConfigurationView(profileManager: profileManager)
        }
    }
}

