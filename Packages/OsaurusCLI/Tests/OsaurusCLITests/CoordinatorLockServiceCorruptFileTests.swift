//
//  CoordinatorLockServiceCorruptFileTests.swift
//  osaurus
//
//  A single corrupt/truncated lock file must not break listing, status, and
//  reaping for every other resource — and must be garbage-collectable.
//

import Foundation
import XCTest

@testable import OsaurusCLICore

final class CoordinatorLockServiceCorruptFileTests: XCTestCase {

    func testCorruptLockFileIsToleratedAndReapable() throws {
        let service = CoordinatorLockService(paths: try temporaryPaths())

        // A valid lock so the locks directory exists alongside the bad file.
        _ = try service.acquire(resource: "good", owner: "worker-a")

        // Plant a corrupt lock file using the real naming scheme.
        let badURL = service.paths.lockFile(for: "poison")
        try Data("{ this is not valid json".utf8).write(to: badURL)

        // Before the fix `list()` rethrew the decode error and aborted the whole
        // scan; it must now skip the corrupt file and return the good lock.
        XCTAssertEqual(try service.list().map(\.resource), ["good"])

        // `reapExpired()` is the auto-cleanup path; before the fix it threw before
        // it could remove anything, so the poison file could never be reaped.
        XCTAssertNoThrow(try service.reapExpired())
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: badURL.path),
            "the corrupt lock file should be garbage-collected by reapExpired()"
        )

        // The valid, non-expired lock is untouched.
        XCTAssertEqual(try service.list().map(\.resource), ["good"])
    }
}
