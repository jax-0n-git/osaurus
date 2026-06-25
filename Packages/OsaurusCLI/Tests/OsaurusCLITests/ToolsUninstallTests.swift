import Foundation
import XCTest

@testable import OsaurusCLICore

final class ToolsUninstallTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osaurus-uninstall-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func resolved(_ path: URL?) -> String? {
        path?.resolvingSymlinksInPath().path
    }

    /// A bare plugin name must never resolve to a same-named directory in the
    /// current working directory (that would delete the wrong directory).
    func testBareNameDoesNotResolveToCurrentDirectory() throws {
        let fm = FileManager.default
        let cwd = tempDir()
        let root = tempDir()  // empty tools root — no matching plugin
        try fm.createDirectory(
            at: cwd.appendingPathComponent("collide", isDirectory: true),
            withIntermediateDirectories: true
        )

        let saved = fm.currentDirectoryPath
        fm.changeCurrentDirectoryPath(cwd.path)
        defer { fm.changeCurrentDirectoryPath(saved) }

        XCTAssertNil(ToolsUninstall.resolveTargetDirectory("collide", root: root))
    }

    /// An explicit filesystem path is still honored.
    func testExplicitAbsolutePathIsResolved() throws {
        let fm = FileManager.default
        let base = tempDir()
        let target = base.appendingPathComponent("plug", isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)

        XCTAssertEqual(
            resolved(ToolsUninstall.resolveTargetDirectory(target.path, root: tempDir())),
            resolved(target)
        )
    }

    /// A relative "./name" path is treated as a path, not a plugin id.
    func testDotSlashNameIsPathMode() throws {
        let fm = FileManager.default
        let cwd = tempDir()
        let dir = cwd.appendingPathComponent("rel", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let saved = fm.currentDirectoryPath
        fm.changeCurrentDirectoryPath(cwd.path)
        defer { fm.changeCurrentDirectoryPath(saved) }

        XCTAssertEqual(
            resolved(ToolsUninstall.resolveTargetDirectory("./rel", root: tempDir())),
            resolved(dir)
        )
    }

    /// A folder directly under the tools root resolves by its (plugin-id) name.
    func testFolderUnderRootResolves() throws {
        let fm = FileManager.default
        let root = tempDir()
        let plugin = root.appendingPathComponent("my-plugin", isDirectory: true)
        try fm.createDirectory(at: plugin, withIntermediateDirectories: true)

        XCTAssertEqual(
            resolved(ToolsUninstall.resolveTargetDirectory("my-plugin", root: root)),
            resolved(plugin)
        )
    }
}
