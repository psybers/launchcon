import XCTest
@testable import LaunchCon

final class JobListParserTests: XCTestCase {

    func testParsesStandardListOutput() {
        let output = """
        PID\tStatus\tLabel
        -\t0\tcom.apple.cfprefsd.xpc.agent
        1234\t1\tcom.example.myagent
        -\t-9\tcom.apple.disabled_thing
        """
        let rows = JobListParser.parse(output)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].label, "com.apple.cfprefsd.xpc.agent")
        XCTAssertNil(rows[0].pid)
        XCTAssertEqual(rows[0].status, 0)
        XCTAssertEqual(rows[1].pid, 1234)
        XCTAssertEqual(rows[1].status, 1)
        XCTAssertEqual(rows[2].label, "com.apple.disabled_thing")
        XCTAssertEqual(rows[2].status, -9)
    }

    func testParsesSpaceSeparatedOutput() {
        let output = """
        PID Status Label
        42 0 com.example.spaces
        """
        let rows = JobListParser.parse(output)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].label, "com.example.spaces")
        XCTAssertEqual(rows[0].pid, 42)
    }

    func testEmptyOutput() {
        XCTAssertTrue(JobListParser.parse("").isEmpty)
    }

    func testSkipsHeaderOnly() {
        let rows = JobListParser.parse("PID\tStatus\tLabel\n")
        XCTAssertTrue(rows.isEmpty)
    }
}

final class DomainPrintParserTests: XCTestCase {

    func testParsesServicesBlock() {
        let output = """
        gui/503 = {
        \ttype = login
        \tservice count = 3

        \tservices = {
        \t\t       0      0 \tcom.example.notrunning
        \t\t   41614   (pe) \tcom.apple.runningagent
        \t\t       -      1 \tcom.example.exited
        \t}

        \tendpoints = {
        \t}
        }
        """
        let rows = DomainPrintParser.services(output)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].label, "com.example.notrunning")
        XCTAssertNil(rows[0].pid)
        XCTAssertEqual(rows[0].status, 0)
        XCTAssertEqual(rows[1].label, "com.apple.runningagent")
        XCTAssertEqual(rows[1].pid, 41614)
        XCTAssertNil(rows[1].status)
        XCTAssertEqual(rows[2].label, "com.example.exited")
        XCTAssertNil(rows[2].pid)
        XCTAssertEqual(rows[2].status, 1)
    }

    func testNoServicesBlock() {
        XCTAssertTrue(DomainPrintParser.services("foo = {\n\tbar = 1\n}\n").isEmpty)
    }
}

final class DisabledListParserTests: XCTestCase {

    func testParsesDisabledServices() {
        let output = """
        disabled services = {
        \t"com.example.off" => disabled
        \t"com.example.on" => enabled
        \t"com.example.alsooff" => disabled
        }
        """
        let disabled = DisabledListParser.parse(output)
        XCTAssertEqual(disabled, ["com.example.off", "com.example.alsooff"])
    }

    func testEmpty() {
        XCTAssertTrue(DisabledListParser.parse("disabled services = {\n}\n").isEmpty)
    }
}

final class LaunchdDomainTests: XCTestCase {

    func testGUIServiceReference() {
        let domain = LaunchdDomain.gui(uid: 501)
        XCTAssertEqual(domain.service("com.example.agent"), "gui/501/com.example.agent")
        XCTAssertEqual(domain.rawValue, "gui/501")
    }

    func testCurrentUserDomain() {
        XCTAssertEqual(LaunchdDomain.guiCurrentUser.rawValue, "gui/\(getuid())")
    }
}

final class PlistTests: XCTestCase {

    func testLoadAndLabel() throws {
        let plist: [String: Any] = [
            "Label": "com.example.test",
            "ProgramArguments": ["/bin/echo", "hi"],
            "RunAtLoad": true,
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }

        try Plist.save(plist, to: url)
        let loaded = try XCTUnwrap(Plist.load(url))
        XCTAssertEqual(Plist.label(in: loaded), "com.example.test")
        XCTAssertEqual(loaded["RunAtLoad"] as? Bool, true)
    }

    func testLoadMissingFileReturnsNil() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).plist")
        XCTAssertNil(Plist.load(url))
    }

    func testValuesEqual() {
        XCTAssertTrue(Plist.valuesEqual("a", "a"))
        XCTAssertTrue(Plist.valuesEqual(9, NSNumber(value: 9)))
        XCTAssertTrue(Plist.valuesEqual(true, NSNumber(value: true)))
        XCTAssertFalse(Plist.valuesEqual(true, 1)) // bool vs int must differ
        XCTAssertFalse(Plist.valuesEqual("a", "b"))
        XCTAssertTrue(Plist.valuesEqual(["a", "b"], ["a", "b"]))
        XCTAssertTrue(Plist.valuesEqual(
            ["Hour": 9, "Minute": 0],
            ["Hour": NSNumber(value: 9), "Minute": NSNumber(value: 0)]
        ))
        XCTAssertFalse(Plist.valuesEqual(["a": 1], ["a": 1, "b": 2]))
        XCTAssertTrue(Plist.valuesEqual(nil, nil))
        XCTAssertFalse(Plist.valuesEqual("x", nil))
    }
}

final class ServicePrintParserTests: XCTestCase {

    func testParsesTopLevelProperties() {
        let output = """
        gui/503/com.example.foo = {
        \tactive count = 0
        \tpath = /Users/x/Library/LaunchAgents/foo.plist
        \ttype = LaunchAgent
        \tstate = not running
        \n
        \tprogram = /bin/echo
        \targuments = {
        \t\t/bin/echo
        \t\thi there
        \t}
        \n
        \tstdout path = /tmp/out.log
        \tstderr path = /dev/null
        \truns = 3
        \tlast exit code = (never exited)
        \tproperties = inferred program
        }
        """
        let props = ServicePrintParser.properties(output)
        XCTAssertEqual(props["state"], "not running")
        XCTAssertEqual(props["program"], "/bin/echo")
        XCTAssertEqual(props["path"], "/Users/x/Library/LaunchAgents/foo.plist")
        XCTAssertEqual(props["stdout path"], "/tmp/out.log")
        XCTAssertEqual(props["stderr path"], "/dev/null")
        XCTAssertEqual(props["runs"], "3")
        XCTAssertEqual(props["last exit code"], "(never exited)")
        XCTAssertEqual(props["properties"], "inferred program")
        // Nested block contents must not leak into top-level properties.
        XCTAssertNil(props["/bin/echo"])
        XCTAssertEqual(props["arguments"], "(…)")
        XCTAssertNil(props["gui/503/com.example.foo"])
    }

    func testEmptyOutput() {
        XCTAssertTrue(ServicePrintParser.properties("").isEmpty)
    }
}

final class JobValidatorTests: XCTestCase {

    private func makeJob(plist: [String: Any]?, label: String = "com.example.test") throws -> Job {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(label).plist")
        if let plist { try Plist.save(plist, to: url) }
        return Job(
            label: label, pid: nil, lastExitStatus: nil,
            domain: .guiCurrentUser, plistPath: url.path,
            isLoaded: false, isDisabled: false, plist: plist
        )
    }

    func testMissingLabel() throws {
        let job = try makeJob(plist: ["Program": "/bin/echo"])
        let diagnostics = JobValidator.validate(job)
        XCTAssertTrue(diagnostics.contains {
            $0.severity == .error && $0.key == "Label"
        })
    }

    func testLabelFilenameMismatch() throws {
        let job = try makeJob(plist: [
            "Label": "com.example.other",
            "Program": "/bin/echo",
        ])
        let diagnostics = JobValidator.validate(job)
        XCTAssertTrue(diagnostics.contains {
            $0.severity == .warning && $0.message.contains("doesn't match filename")
        })
    }

    func testMissingProgram() throws {
        let job = try makeJob(plist: ["Label": "com.example.test"])
        let diagnostics = JobValidator.validate(job)
        XCTAssertTrue(diagnostics.contains {
            $0.severity == .error && $0.message.contains("Neither Program")
        })
    }

    func testProgramNotFound() throws {
        let job = try makeJob(plist: [
            "Label": "com.example.test",
            "Program": "/nonexistent/binary",
        ])
        let diagnostics = JobValidator.validate(job)
        XCTAssertTrue(diagnostics.contains {
            $0.severity == .error && $0.message.contains("Program not found")
        })
    }

    func testValidJobHasNoErrors() throws {
        let job = try makeJob(plist: [
            "Label": "com.example.test",
            "Program": "/bin/echo",
        ])
        let diagnostics = JobValidator.validate(job)
        XCTAssertFalse(diagnostics.contains { $0.severity == .error })
    }

    func testBadCalendarInterval() throws {
        let job = try makeJob(plist: [
            "Label": "com.example.test",
            "Program": "/bin/echo",
            "StartCalendarInterval": ["Hour": "nine"],
        ])
        let diagnostics = JobValidator.validate(job)
        XCTAssertTrue(diagnostics.contains {
            $0.key == "StartCalendarInterval" && $0.severity == .error
        })
    }
}

final class LogTailTests: XCTestCase {

    func testTailReturnsLastLines() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("log-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let content = (1...1000).map { "line \($0)" }.joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)

        let tail = try XCTUnwrap(LogTail.tail(path: url.path, maxLines: 10))
        let lines = tail.split(separator: "\n")
        XCTAssertEqual(lines.count, 10)
        XCTAssertEqual(lines.last, "line 1000")
    }

    func testTailMissingFile() {
        XCTAssertNil(LogTail.tail(path: "/nonexistent/\(UUID().uuidString)"))
    }
}
