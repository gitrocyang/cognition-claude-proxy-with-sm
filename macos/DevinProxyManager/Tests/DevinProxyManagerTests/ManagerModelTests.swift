import XCTest
@testable import DevinProxyManager

@MainActor
final class ManagerModelTests: XCTestCase {
    func testChecksRunningServiceBeforeMenuOpens() async {
        let model = ManagerModel(snapshotProvider: {
            ServiceSnapshot(state: .running, detail: "test", autoStart: true)
        })
        for _ in 0..<20 {
            if model.snapshot.state == .running { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.snapshot.state, .running)
    }

    func testDoesNotPollWhileMenuIsClosed() async {
        let lock = NSLock()
        var checks = 0
        let model = ManagerModel(snapshotProvider: {
            lock.lock()
            defer { lock.unlock() }
            checks += 1
            return ServiceSnapshot(state: .stopped, detail: "test", autoStart: false)
        })
        for _ in 0..<20 {
            if lock.withLock({ checks }) > 0 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        _ = model
        try? await Task.sleep(nanoseconds: 5_300_000_000)
        let observedChecks = lock.withLock { checks }
        XCTAssertEqual(observedChecks, 1)
    }
}
