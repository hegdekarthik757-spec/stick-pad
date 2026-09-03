import Foundation

/// A pocket-sized assertion harness. XCTest only ships with Xcode, and this
/// project is meant to build with the Command Line Tools, so the suite runs as
/// an ordinary executable and reports through this.
enum T {
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var currentSuite = ""

    static func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        print("\n  \(name)")
        do {
            try body()
        } catch {
            record("threw unexpectedly: \(error)")
        }
    }

    static func test(_ name: String, _ body: () throws -> Void) {
        let before = failures.count
        do {
            try body()
        } catch {
            record("\(name): threw unexpectedly — \(error)")
        }
        let passed = failures.count == before
        print("    \(passed ? "✓" : "✗") \(name)")
    }

    static func record(_ message: String) {
        failures.append("[\(currentSuite)] \(message)")
    }

    static func expect(_ condition: Bool, _ description: String, line: UInt = #line) {
        checks += 1
        if !condition { record("line \(line): \(description)") }
    }

    static func equal<V: Equatable>(_ actual: V, _ expected: V, _ description: String, line: UInt = #line) {
        checks += 1
        if actual != expected {
            record("line \(line): \(description) — expected \(expected), got \(actual)")
        }
    }

    static func notEqual<V: Equatable>(_ a: V, _ b: V, _ description: String, line: UInt = #line) {
        checks += 1
        if a == b { record("line \(line): \(description) — both values were \(a)") }
    }

    static func throwsError(_ description: String, line: UInt = #line, _ body: () throws -> Void) {
        checks += 1
        do {
            try body()
            record("line \(line): \(description) — expected an error, none was thrown")
        } catch {
            // expected
        }
    }

    static func report() -> Int32 {
        print("\n" + String(repeating: "─", count: 52))
        if failures.isEmpty {
            print("  All \(checks) checks passed.")
            return 0
        }
        print("  \(failures.count) failure(s) out of \(checks) checks:")
        for failure in failures { print("    • \(failure)") }
        return 1
    }
}
