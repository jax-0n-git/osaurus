//
//  MCPBundleManifestDesktopFormatTests.swift
//  osaurus
//
//  The desktop-client integration format (`server.mcp_config`) should accept an
//  omitted `args`, exactly like the standard MCPB `entry` format does.
//

import Foundation
import XCTest

@testable import OsaurusCLICore

final class MCPBundleManifestDesktopFormatTests: XCTestCase {

    /// A desktop-format manifest whose server command takes no arguments omits
    /// `args`. The standard `EntryPoint` defaults a missing `args` to `[]`; the
    /// desktop-format `MCPConfig` must do the same instead of failing to decode.
    func testDesktopFormatManifestWithoutArgsDecodes() throws {
        let json = """
            {
              "name": "x",
              "version": "1.0",
              "server": { "type": "stdio", "mcp_config": { "command": "my-mcp" } }
            }
            """
        let manifest = try JSONDecoder().decode(MCPBundleManifest.self, from: Data(json.utf8))
        let entry = manifest.getEntryPoint()
        XCTAssertEqual(entry.command, "my-mcp")
        XCTAssertEqual(entry.args, [])
        XCTAssertNil(entry.env)
    }

    /// Regression guard: a desktop-format manifest that does provide `args`/`env`
    /// continues to decode them.
    func testDesktopFormatManifestWithArgsStillDecodes() throws {
        let json = """
            {
              "name": "x",
              "version": "1.0",
              "server": {
                "type": "stdio",
                "mcp_config": { "command": "my-mcp", "args": ["--port", "3000"], "env": { "K": "v" } }
              }
            }
            """
        let manifest = try JSONDecoder().decode(MCPBundleManifest.self, from: Data(json.utf8))
        let entry = manifest.getEntryPoint()
        XCTAssertEqual(entry.command, "my-mcp")
        XCTAssertEqual(entry.args, ["--port", "3000"])
        XCTAssertEqual(entry.env, ["K": "v"])
    }
}
