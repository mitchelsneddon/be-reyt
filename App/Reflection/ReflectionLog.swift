#if DEBUG
    import Foundation
    import OSLog

    /// Debug-only diagnostics for reflection runs. Never carries journal text: only error type and case names,
    /// pass kinds, token counts and timings.
    enum ReflectionLog {
        private static let logger = Logger(subsystem: "local.mitchel.bereyt", category: "reflection")

        static func note(_ message: String) { logger.notice("\(message, privacy: .public)") }

        /// "LanguageModelError.contextSizeExceeded" style label: type and case name, no payload.
        static func label(_ error: Error) -> String {
            let described = String(describing: error)
            let caseName = described.prefix { $0 != "(" && $0 != "\n" }
            return "\(type(of: error)).\(caseName) \(Task.isCancelled ? "[task cancelled]" : "")"
        }
    }
#endif
