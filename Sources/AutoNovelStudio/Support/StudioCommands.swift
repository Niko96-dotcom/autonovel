import AppKit
import SwiftUI

enum TextFinding {
    static func showFindPanel() {
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
    }
}

private struct StudioSaveActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var studioSaveAction: (() -> Void)? {
        get { self[StudioSaveActionKey.self] }
        set { self[StudioSaveActionKey.self] = newValue }
    }
}

struct StudioCommands: Commands {
    @Bindable var store: StudioStore
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.studioSaveAction) private var saveAction

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Window") {
                openWindow(id: "studio-main")
            }
            .keyboardShortcut("n")

            Button("Save") { saveAction?() }
                .keyboardShortcut("s")
                .disabled(saveAction == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") { TextFinding.showFindPanel() }
                .keyboardShortcut("f")
        }

        SidebarCommands()

        CommandMenu("Novel") {
            Button("Check Connection") { store.runModelCheck() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(store.runner.isRunning)
            Button("Run Current Phase") { store.runCurrentPhase() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.runner.isRunning || !store.seedIsReady)
            Divider()
            Button("Stop Current Process") { store.runner.stop() }
                .disabled(!store.runner.isRunning)
        }

        CommandGroup(replacing: .help) {
            Button("AutoNovel Studio Help") { store.showHelp = true }
        }
    }
}

enum StudioWindowHygiene {
    static func closePlaceholderWindows() {
        for window in NSApp.windows {
            guard shouldClose(window) else { continue }
            window.ignoresMouseEvents = true
            window.orderOut(nil)
            window.close()
        }
    }

    private static func shouldClose(_ window: NSWindow) -> Bool {
        if window.isSheet || window.sheetParent != nil { return false }
        if window.styleMask.contains(.titled), !window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        let size = window.frame.size
        let classicPlaceholder = abs(size.width - 500) < 2 && abs(size.height - 500) < 2
        return classicPlaceholder && window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
