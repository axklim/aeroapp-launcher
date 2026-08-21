import Foundation

// A tiny test runner. XCTest and swift-testing both ship only with Xcode, and this
// project builds with the Command Line Tools alone — see test.sh.

enum Harness {
    private(set) static var failures = 0
    private(set) static var passed = 0
    private static var currentTest = ""

    static func test(_ name: String, _ body: () throws -> Void) {
        currentTest = name
        let before = failures
        do {
            try body()
        } catch {
            fail("threw \(error)")
        }
        if failures == before {
            passed += 1
        } else {
            print("FAIL \(name)")
        }
    }

    static func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        failures += 1
        print("  \(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line): \(currentTest): \(message)")
    }

    static func finish() -> Never {
        print("\(passed) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    Harness.test(name, body)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "expected true", file: StaticString = #filePath, line: UInt = #line) {
    if !condition() { Harness.fail(message(), file: file, line: line) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected {
        let suffix = message().isEmpty ? "" : " — \(message())"
        Harness.fail("expected \(expected), got \(actual)\(suffix)", file: file, line: line)
    }
}

func expectNil<T>(_ actual: T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    if let actual {
        Harness.fail("expected nil, got \(actual) \(message())", file: file, line: line)
    }
}

func expectThrows<E: Error>(_ type: E.Type = E.self, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void, check: (E) -> Bool = { _ in true }) {
    do {
        try body()
        Harness.fail("expected \(E.self) to be thrown", file: file, line: line)
    } catch let error as E {
        if !check(error) { Harness.fail("thrown \(error) failed check", file: file, line: line) }
    } catch {
        Harness.fail("expected \(E.self), got \(error)", file: file, line: line)
    }
}
