import Foundation
import OSLog

/// Shared OSLog loggers for Studio runtime telemetry.
/// Filter with: `log stream --predicate 'subsystem == "org.nousresearch.autonovelstudio"'`
enum StudioLog {
    static let subsystem =
        Bundle.main.bundleIdentifier ?? "org.nousresearch.autonovelstudio"

    static let sidebar = Logger(subsystem: subsystem, category: "Sidebar")
    static let pipeline = Logger(subsystem: subsystem, category: "Pipeline")
    static let windowing = Logger(subsystem: subsystem, category: "Windowing")
}
