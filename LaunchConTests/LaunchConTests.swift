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
}
