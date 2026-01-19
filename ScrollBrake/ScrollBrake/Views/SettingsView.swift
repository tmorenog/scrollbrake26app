//
//  SettingsView.swift
//  ScrollBrake
//
//  Settings screen for configuring session limits, break window,
//  and reward window durations.
//

import SwiftUI

struct SettingsView: View {
    // Settings values bound to persistence
    @State private var sessionLimitMinutes: Double = 5
    @State private var breakWindowSeconds: Double = 20
    @State private var rewardWindowMinutes: Double = 2

    @EnvironmentObject var monitoringManager: MonitoringManager

    private let persistence = PersistenceManager.shared

    var body: some View {
        NavigationView {
            Form {
                // Session Limit Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Session Limit")
                            Spacer()
                            Text("\(Int(sessionLimitMinutes)) minutes")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }

                        Slider(value: $sessionLimitMinutes, in: 1...30, step: 1)
                            .onChange(of: sessionLimitMinutes) { newValue in
                                persistence.sessionLimitMinutes = Int(newValue)
                                monitoringManager.updateSettings()
                            }

                        Text("How long you can use monitored apps before they're blocked.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Time Limits")
                }

                // Break Window Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Break Window")
                            Spacer()
                            Text("\(Int(breakWindowSeconds)) seconds")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }

                        Slider(value: $breakWindowSeconds, in: 5...120, step: 5)
                            .onChange(of: breakWindowSeconds) { newValue in
                                persistence.breakWindowSeconds = Int(newValue)
                                monitoringManager.updateSettings()
                            }

                        Text("If you leave monitored apps for this long, your session resets. Taking breaks is good!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Break Detection")
                }

                // Reward Window Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Reward Window")
                            Spacer()
                            Text("\(Int(rewardWindowMinutes)) minutes")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }

                        Slider(value: $rewardWindowMinutes, in: 1...10, step: 1)
                            .onChange(of: rewardWindowMinutes) { newValue in
                                persistence.rewardWindowMinutes = Int(newValue)
                                monitoringManager.updateSettings()
                            }

                        Text("After solving the math challenge, you get this much free time before the session timer starts again.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Rewards")
                }

                // Presets Section
                Section {
                    Button("Quick Break (3 min limit)") {
                        applyPreset(sessionLimit: 3, breakWindow: 15, rewardWindow: 1)
                    }

                    Button("Standard (5 min limit)") {
                        applyPreset(sessionLimit: 5, breakWindow: 20, rewardWindow: 2)
                    }

                    Button("Relaxed (10 min limit)") {
                        applyPreset(sessionLimit: 10, breakWindow: 30, rewardWindow: 3)
                    }

                    Button("Focus Mode (1 min limit)") {
                        applyPreset(sessionLimit: 1, breakWindow: 10, rewardWindow: 1)
                    }
                    .foregroundColor(.orange)
                } header: {
                    Text("Presets")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("MVP")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("ScrollBrake uses Apple's Screen Time APIs to help you manage your app usage. All data stays on your device.")
                }

                // Debug Section
                Section {
                    Button("Reset All Settings") {
                        resetToDefaults()
                    }
                    .foregroundColor(.red)

                    Button("Clear Session Data") {
                        monitoringManager.resetSession()
                    }
                    .foregroundColor(.orange)
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Use these options to troubleshoot issues or start fresh.")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                loadCurrentSettings()
            }
        }
    }

    // MARK: - Helpers
    private func loadCurrentSettings() {
        sessionLimitMinutes = Double(persistence.sessionLimitMinutes)
        breakWindowSeconds = Double(persistence.breakWindowSeconds)
        rewardWindowMinutes = Double(persistence.rewardWindowMinutes)
    }

    private func applyPreset(sessionLimit: Int, breakWindow: Int, rewardWindow: Int) {
        withAnimation {
            sessionLimitMinutes = Double(sessionLimit)
            breakWindowSeconds = Double(breakWindow)
            rewardWindowMinutes = Double(rewardWindow)
        }

        persistence.sessionLimitMinutes = sessionLimit
        persistence.breakWindowSeconds = breakWindow
        persistence.rewardWindowMinutes = rewardWindow

        monitoringManager.updateSettings()
    }

    private func resetToDefaults() {
        applyPreset(sessionLimit: 5, breakWindow: 20, rewardWindow: 2)
    }
}

#Preview {
    SettingsView()
        .environmentObject(MonitoringManager.shared)
}
