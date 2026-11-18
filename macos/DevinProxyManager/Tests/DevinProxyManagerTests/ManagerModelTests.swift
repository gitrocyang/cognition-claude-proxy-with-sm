import XCTest
@testable import DevinProxyManager

@MainActor
final class ManagerModelTests: XCTestCase {
    func testChecksRunningServiceBeforeMenuOpens() async {
        let model = ManagerModel(snapshotProvider: {
            ServiceSnapshot(state: .running, detail: "test", autoStart: true)
        }, pollInterval: 0.05)
        for _ in 0..<20 {
            if model.snapshot.state == .running { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.snapshot.state, .running)
    }

    func testKeepsCheckingWhileMenuIsClosed() async {
        let lock = NSLock()
        var checks = 0
        let model = ManagerModel(snapshotProvider: {
            lock.lock()
            defer { lock.unlock() }
            checks += 1
            return ServiceSnapshot(state: checks == 1 ? .stopped : .running,
                                   detail: "test", autoStart: false)
        }, pollInterval: 0.05)
        for _ in 0..<30 {
            if model.snapshot.state == .running { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.snapshot.state, .running)
        let observedChecks = lock.withLock { checks }
        XCTAssertGreaterThanOrEqual(observedChecks, 2)
    }
}
