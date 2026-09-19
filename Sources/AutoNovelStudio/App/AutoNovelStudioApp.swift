import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSHelpManager.shared.registerBooks(in: Bundle.main)
        StudioLog.windowing.info("App finished launching")
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
        // Role: primary NavigationSplitView workspace.
        // Keep titled chrome + unified toolbar + system restoration (do not hide
        // title/toolbar or disable restore on the main window).
        // macOS 15+ Scene APIs (defaultWindowPlacement, windowIdealPlacement,
        // restorationBehavior) are skipped: SceneBuilder cannot if/else-gate them
        // while targeting macOS 14, and plan allows skip over unsafe use.
        WindowGroup("AutoNovel Studio", id: "studio-main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 640)
                .onAppear {
                    StudioLog.windowing.info("Main studio window appeared")
                }
                .task { store.startMonitoring() }
        }
        .defaultSize(width: 1_000, height: 760)
        .defaultPosition(.center)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands {
            StudioCommands(store: store)
        }

        #if os(macOS)
        // Role: preferences utility (always reachable from the app menu).
        // Prefer content-sized chrome; minimize disabled on macOS 15+ via view API.
        Settings {
            ProviderSettingsView(store: store)
                .modifier(StudioSettingsWindowBehavior())
        }
        .defaultSize(width: 640, height: 720)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        #endif
    }
}

/// Settings is a fixed-purpose utility window: disable minimize when the API exists.
private struct StudioSettingsWindowBehavior: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.windowMinimizeBehavior(.disabled)
        } else {
            content
        }
    }
}
