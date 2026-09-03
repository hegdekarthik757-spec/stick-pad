import AppKit

/// The single public entry point. Everything else stays internal to the module
/// so the test runner can reach it with `@testable import` without the app's
/// internals becoming public API.
@MainActor
public enum StickPadApp {
    public static func run(arguments: [String] = CommandLine.arguments) {
        let app = NSApplication.shared

        // Development helper: draw sample notes to PNG and exit.
        if let i = arguments.firstIndex(of: "--render-preview"), arguments.count > i + 1 {
            app.setActivationPolicy(.prohibited)
            PreviewRenderer.run(outputDirectory: arguments[i + 1])
            exit(0)
        }

        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
