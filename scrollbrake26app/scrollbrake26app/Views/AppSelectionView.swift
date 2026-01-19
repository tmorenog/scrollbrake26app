//
//  AppSelectionView.swift
//  ScrollBrake
//
//  Allows users to select which apps/categories to monitor using
//  Apple's FamilyActivityPicker. The picker provides a system UI
//  for selecting apps without exposing app identifiers to our code.
//

import SwiftUI
import FamilyControls

struct AppSelectionView: View {
    @EnvironmentObject var monitoringManager: MonitoringManager

    // FamilyActivitySelection is the model for selected apps/categories
    @State private var selection = FamilyActivitySelection()

    // Controls whether the picker sheet is shown
    @State private var isPickerPresented = false

    // Persistence manager for saving selections
    private let persistence = PersistenceManager.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header explanation
                headerSection

                // Current selection summary
                selectionSummary

                // Pick apps button
                pickAppsButton

                // Apply and monitor button
                applyButton

                Spacer()

                // Info footer
                infoFooter
            }
            .padding()
            .navigationTitle("Select Apps")
            .onAppear {
                // Load saved selection on appear
                loadSavedSelection()
            }
            // FamilyActivityPicker presented as a sheet
            .familyActivityPicker(
                isPresented: $isPickerPresented,
                selection: $selection
            )
            .onChange(of: selection) { newSelection in
                // Auto-save when selection changes
                saveSelection(newSelection)
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "apps.iphone")
                .font(.system(size: 50))
                .foregroundColor(.blue)

            Text("Choose Apps to Limit")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Select the apps you want to take breaks from. When you hit your session limit, these apps will be blocked until you solve a quick math problem.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top)
    }

    // MARK: - Selection Summary
    private var selectionSummary: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Currently Selected")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 20) {
                // Apps count
                VStack {
                    Text("\(selection.applicationTokens.count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("Apps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 40)

                // Categories count
                VStack {
                    Text("\(selection.categoryTokens.count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                    Text("Categories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 40)

                // Web domains count
                VStack {
                    Text("\(selection.webDomainTokens.count)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("Websites")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Pick Apps Button
    private var pickAppsButton: some View {
        Button(action: {
            isPickerPresented = true
        }) {
            HStack {
                Image(systemName: "plus.app.fill")
                Text("Select Apps & Categories")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
        }
    }

    // MARK: - Apply Button
    private var applyButton: some View {
        Button(action: {
            applySelectionAndStartMonitoring()
        }) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                Text("Apply & Start Monitoring")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(hasSelection ? Color.green : Color.gray)
            .cornerRadius(12)
        }
        .disabled(!hasSelection)
    }

    // MARK: - Info Footer
    private var infoFooter: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Tip")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            Text("You can select entire categories like \"Social\" to catch apps like TikTok, Instagram, and YouTube all at once, or pick specific apps individually.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    // MARK: - Helpers
    private var hasSelection: Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
    }

    private func loadSavedSelection() {
        if let saved = persistence.loadFamilyActivitySelection() {
            selection = saved
        }
    }

    private func saveSelection(_ newSelection: FamilyActivitySelection) {
        persistence.saveFamilyActivitySelection(newSelection)
    }

    private func applySelectionAndStartMonitoring() {
        // Save the selection
        saveSelection(selection)

        // Update the monitoring manager with the new selection
        monitoringManager.updateSelection(selection)

        // Start monitoring if not already
        if !monitoringManager.isMonitoring {
            monitoringManager.startMonitoring()
        }
    }
}

#Preview {
    AppSelectionView()
        .environmentObject(MonitoringManager.shared)
}
