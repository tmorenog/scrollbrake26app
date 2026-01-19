//
//  ContentView.swift
//  ScrollBrake
//
//  Main content view that handles navigation between different screens
//  and shows the math gate when apps are shielded.
//

import SwiftUI
import FamilyControls

struct ContentView: View {
    @EnvironmentObject var authorizationManager: AuthorizationManager
    @EnvironmentObject var monitoringManager: MonitoringManager
    @EnvironmentObject var shieldManager: ShieldManager

    @State private var showMathGate = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            // Main tab view (only visible when authorized and no math gate)
            if authorizationManager.authorizationStatus == .approved {
                mainContent
            } else {
                authorizationView
            }

            // Math gate overlay - shown when shield is active
            if showMathGate {
                MathGateView(isPresented: $showMathGate)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut, value: showMathGate)
        .onReceive(NotificationCenter.default.publisher(for: .showMathGate)) { _ in
            withAnimation {
                showMathGate = true
            }
        }
        .onAppear {
            // Check if we should show math gate on appear
            let persistence = PersistenceManager.shared
            if persistence.isShieldActive && !persistence.challengeSolvedRecently {
                showMathGate = true
            }
        }
    }

    // MARK: - Main Content (Tab View)
    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            // Home / Status Tab
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            // App Selection Tab
            AppSelectionView()
                .tabItem {
                    Label("Apps", systemImage: "app.badge.checkmark")
                }
                .tag(1)

            // Settings Tab
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
    }

    // MARK: - Authorization Request View
    private var authorizationView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hourglass.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("scrollbrake26app")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Take control of your screen time")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            VStack(spacing: 16) {
                Text("Screen Time Access Required")
                    .font(.headline)

                Text("scrollbrake26app needs Screen Time access to monitor and limit app usage. This data stays on your device.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: {
                    Task {
                        await authorizationManager.requestAuthorization()
                    }
                }) {
                    Text("Enable Screen Time Access")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)

                if authorizationManager.authorizationStatus == .denied {
                    Text("Access was denied. Please enable in Settings > Screen Time > scrollbrake26app")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Home View
struct HomeView: View {
    @EnvironmentObject var monitoringManager: MonitoringManager
    @EnvironmentObject var shieldManager: ShieldManager

    private let persistence = PersistenceManager.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Status Card
                    statusCard

                    // Session Info Card
                    sessionInfoCard

                    // Quick Actions
                    quickActionsCard
                }
                .padding()
            }
            .navigationTitle("scrollbrake26app")
        }
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: monitoringManager.isMonitoring ? "eye.fill" : "eye.slash.fill")
                    .font(.title2)
                    .foregroundColor(monitoringManager.isMonitoring ? .green : .gray)

                Text(monitoringManager.isMonitoring ? "Monitoring Active" : "Monitoring Inactive")
                    .font(.headline)

                Spacer()
            }

            HStack {
                Text("Selected apps: \(persistence.selectedAppsCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }

            if persistence.isShieldActive {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.red)
                    Text("Apps are currently blocked")
                        .font(.subheadline)
                        .foregroundColor(.red)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var sessionInfoCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Session Limits")
                    .font(.headline)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("Session Limit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(persistence.sessionLimitMinutes) min")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Break Window")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(persistence.breakWindowSeconds) sec")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Reward Time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(persistence.rewardWindowMinutes) min")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var quickActionsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Quick Actions")
                    .font(.headline)
                Spacer()
            }

            Button(action: {
                if monitoringManager.isMonitoring {
                    monitoringManager.stopMonitoring()
                } else {
                    monitoringManager.startMonitoring()
                }
            }) {
                HStack {
                    Image(systemName: monitoringManager.isMonitoring ? "pause.circle.fill" : "play.circle.fill")
                    Text(monitoringManager.isMonitoring ? "Pause Monitoring" : "Start Monitoring")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(monitoringManager.isMonitoring ? Color.orange : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }

            if persistence.isShieldActive {
                Button(action: {
                    // This will show the math gate
                    NotificationCenter.default.post(name: .showMathGate, object: nil)
                }) {
                    HStack {
                        Image(systemName: "lock.open.fill")
                        Text("Unlock Apps (Solve Challenge)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }

            // Debug: Manual reset (for testing)
            Button(action: {
                shieldManager.removeShield()
                monitoringManager.resetSession()
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Session (Debug)")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray4))
                .foregroundColor(.primary)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthorizationManager.shared)
        .environmentObject(MonitoringManager.shared)
        .environmentObject(ShieldManager.shared)
}
