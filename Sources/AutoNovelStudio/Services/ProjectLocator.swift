import Foundation

enum ProjectLocator {
    static func locate() -> URL {
        if let configured = ProcessInfo.processInfo.environment["AUTONOVEL_PROJECT_DIR"] {
            let url = URL(fileURLWithPath: configured, isDirectory: true)
            if isProject(url) { return url }
        }

        let starts = [
            Bundle.main.bundleURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent(),
        ]
        for start in starts {
            if let project = walkUp(from: start) { return project }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    private static func walkUp(from start: URL) -> URL? {
        var candidate = start.hasDirectoryPath ? start : start.deletingLastPathComponent()
        while candidate.path != "/" {
            if isProject(candidate) { return candidate }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    private static func isProject(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("run_pipeline.py").path)
            && fm.fileExists(atPath: url.appendingPathComponent("state.json").path)
    }
}
