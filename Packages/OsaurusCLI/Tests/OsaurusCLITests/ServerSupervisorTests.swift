import Foundation
import XCTest

@testable import OsaurusCLICore

final class ServerSupervisorTests: XCTestCase {
    /// Records probe outcomes and relaunch calls, and scripts the health sequence.
    private actor Recorder {
        private var healthSequence: [Bool]
        private var index = 0
        private(set) var ensureCount = 0
        private(set) var probeCount = 0

        init(_ healthSequence: [Bool]) {
            self.healthSequence = healthSequence
        }

        func nextHealth() -> Bool {
            defer { index += 1 }
            probeCount += 1
            if index < healthSequence.count { return healthSequence[index] }
            return healthSequence.last ?? true
        }

        func recordEnsure() {
            ensureCount += 1
        }
    }

    private func supervisor(_ rec: Recorder, iterations: Int) -> ServerSupervisor {
        ServerSupervisor(
            port: 1337,
            probeInterval: 0,
            maxIterations: iterations,
            healthCheck: { _ in await rec.nextHealth() },
            ensureServing: { await rec.recordEnsure() },
            sleep: { _ in },
            log: { _ in }
        )
    }

    func testRelaunchesOnEveryDownTick() async {
        let rec = Recorder([false, false, false])
        await supervisor(rec, iterations: 3).run()

        let ensureCount = await rec.ensureCount
        let probeCount = await rec.probeCount
        XCTAssertEqual(probeCount, 3)
        XCTAssertEqual(ensureCount, 3)
    }

    func testNeverRelaunchesWhileHealthy() async {
        let rec = Recorder([true, true, true, true])
        await supervisor(rec, iterations: 4).run()

        let ensureCount = await rec.ensureCount
        XCTAssertEqual(ensureCount, 0)
    }

    func testRelaunchesOnlyWhileDownAcrossRecovery() async {
        // down, down, up, up -> two relaunches, then it leaves the server alone.
        let rec = Recorder([false, false, true, true])
        await supervisor(rec, iterations: 4).run()

        let ensureCount = await rec.ensureCount
        XCTAssertEqual(ensureCount, 2)
    }
}
