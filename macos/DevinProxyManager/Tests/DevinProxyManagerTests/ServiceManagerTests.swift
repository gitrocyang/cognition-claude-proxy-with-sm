import XCTest
import Darwin
@testable import DevinProxyManager

final class ServiceManagerTests: XCTestCase {
    func testLaunchAgentLifecycleOnIsolatedPort() throws {
        guard ProcessInfo.processInfo.environment["CCP_MANAGER_INTEGRATION"] == "1" else { throw XCTSkip("仅在显式启用集成测试时运行") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let prefs = UserDefaults(suiteName: UUID().uuidString)!
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        prefs.set(root.path, forKey: "projectPath")
        prefs.set("/opt/homebrew/bin/node", forKey: "nodePath")
        prefs.set(18765, forKey: "port")
        let manager = ServiceManager(homeOverride: home, preferences: prefs)
        guard !manager.loaded(), manager.listenerPID() == nil else { throw XCTSkip("测试服务或端口已被占用") }
        let credential = home.appendingPathComponent(".local/share/devin/credentials.toml")
        try FileManager.default.createDirectory(at: credential.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test-only\n".utf8).write(to: credential)
        defer {
            try? manager.uninstall()
            try? FileManager.default.removeItem(at: home)
        }
        XCTAssertEqual(manager.snapshot().state, .stopped)
        try manager.start()
        XCTAssertEqual(manager.snapshot().state, .running)
        let firstPID = manager.launchPID()
        try manager.start()
        XCTAssertEqual(manager.launchPID(), firstPID)
        try manager.setAutoStart(true)
        XCTAssertEqual(manager.snapshot().state, .running)
        XCTAssertTrue(manager.snapshot().autoStart)
        try manager.setAutoStart(false)
        XCTAssertEqual(manager.snapshot().state, .running)
        XCTAssertFalse(manager.snapshot().autoStart)
        try manager.stop()
        XCTAssertEqual(manager.snapshot().state, .stopped)
        try manager.start()
        XCTAssertEqual(manager.snapshot().state, .running)
        try manager.restart()
        XCTAssertEqual(manager.snapshot().state, .running)
        let crashedPID = manager.launchPID()
        if let pid = crashedPID { Darwin.kill(pid, SIGKILL) }
        var recovered = false
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.25)
            if manager.snapshot().state == .running, manager.launchPID() != crashedPID { recovered = true; break }
        }
        XCTAssertTrue(recovered, "代理异常退出后应由 launchd 恢复")
        try manager.stop()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(manager.snapshot().state, .stopped)

        let foreign = Process()
        foreign.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/node")
        foreign.arguments = ["-e", "require('http').createServer((_,r)=>r.end('foreign')).listen(18765,'127.0.0.1')"]
        try foreign.run()
        defer { if foreign.isRunning { foreign.terminate(); foreign.waitUntilExit() } }
        for _ in 0..<20 {
            if manager.listenerPID() != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(manager.snapshot().state, .error)
        XCTAssertThrowsError(try manager.start())
        XCTAssertTrue(foreign.isRunning, "端口冲突时不能终止其他进程")
        try manager.uninstall()
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.agentURL.path))
        XCTAssertFalse(manager.loaded())
    }
    func testForeignAgentIsRejected() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let prefs = UserDefaults(suiteName: UUID().uuidString)!
        let manager = ServiceManager(homeOverride: home, preferences: prefs)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: manager.agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<plist><dict></dict></plist>".utf8).write(to: manager.agentURL)
        XCTAssertThrowsError(try manager.agent())
        XCTAssertEqual(manager.snapshot().state, .error)
    }

    func testMissingNodeAndCredentialsAreReportedWithoutReadingContent() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let prefs = UserDefaults(suiteName: UUID().uuidString)!
        prefs.set("/nonexistent/node", forKey: "nodePath")
        prefs.set(home.path, forKey: "projectPath")
        let manager = ServiceManager(homeOverride: home, preferences: prefs)
        defer { try? FileManager.default.removeItem(at: home) }
        let issues = manager.environmentIssues().joined(separator: " ")
        XCTAssertTrue(issues.contains("Node.js"))
        XCTAssertTrue(issues.contains("凭据"))
    }
}
