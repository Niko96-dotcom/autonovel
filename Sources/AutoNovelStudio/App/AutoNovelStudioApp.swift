import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct AutoNovelStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = StudioStore()

    var body: some Scene {
        WindowGroup("AutoNovel Studio") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 640)
                .task { store.startMonitoring() }
                .tint(StudioTheme.accent)
        }
        .defaultSize(width: 1_000, height: 760)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Novel") {
                Button("Check Local Model") { store.runModelCheck() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(store.runner.isRunning)
                Button("Run Current Phase") { store.runCurrentPhase() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(store.runner.isRunning || !store.seedIsReady)
                Divider()
                Button("Stop Current Process") { store.runner.stop() }
                    .disabled(!store.runner.isRunning)
            }
        }

        Settings {
            ProviderSettingsView(store: store)
                .tint(StudioTheme.accent)
        }
    }
}
