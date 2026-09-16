import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSHelpManager.shared.registerBooks(in: Bundle.main)
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didExposeNotification,
        ]
        for name in names {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                StudioWindowHygiene.closePlaceholderWindows()
            }
            windowObservers.append(observer)
        }
        DispatchQueue.main.async {
            StudioWindowHygiene.closePlaceholderWindows()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        StudioWindowHygiene.closePlaceholderWindows()
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
        }
        .defaultSize(width: 1_000, height: 760)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands {
            StudioCommands(store: store)
        }

        Settings {
            ProviderSettingsView(store: store)
        }
        .defaultSize(width: 640, height: 720)
        .windowResizability(.contentMinSize)
    }
}

