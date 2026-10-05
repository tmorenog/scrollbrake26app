//
//  BreakScrollApp.swift
//  BreakScroll
//

import SwiftUI

@main
struct BreakScrollApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                // breakscroll:// links (notification fallback) just open the app;
                // RootView shows whatever intervention is in progress.
                .onOpenURL { _ in model.refresh() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.setActive(phase == .active)
        }
    }
}
