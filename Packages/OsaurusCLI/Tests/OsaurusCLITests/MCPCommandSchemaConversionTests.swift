//
//  MCPCommandSchemaConversionTests.swift
//  osaurus
//
//  Tests the JSON -> MCP.Value conversion the stdio MCP bridge uses when it
//  proxies a tool's `inputSchema` from the local HTTP server to the client.
//

import XCTest

import MCP

@testable import OsaurusCLICore

final class MCPCommandSchemaConversionTests: XCTestCase {

    /// Regression: JSON integers 0 and 1 were miscast to booleans.
    ///
    /// `JSONSerialization` decodes every JSON number (and boolean) as an
    /// `NSNumber`, and in Foundation's bridging both `NSNumber(value: 0) as? Bool`
    /// and `NSNumber(value: 1) as? Bool` succeed. Because the old conversion tried
    /// the `as? Bool` cast before inspecting the `NSNumber`, a plain JSON integer
    /// 0 or 1 anywhere in a tool's schema (e.g. `"minimum": 0`, `"default": 1`,
    /// `"maxItems": 1`, `"exclusiveMinimum": 0`) was emitted to the MCP client as a
    /// JSON boolean (`false`/`true`), corrupting the advertised schema.
    func testProxiedSchemaPreservesIntegerZeroAndOne() throws {
        let raw = """
            {"minimum": 0, "default": 1, "maxItems": 1, "count": 5,
             "ratio": 0.5, "flag": true, "off": false}
            """
        let object = try JSONSerialization.jsonObject(with: Data(raw.utf8))

        guard case let .object(map) = MCPCommand.toMCPValue(from: object) else {
            return XCTFail("expected the schema to convert to an object value")
        }

        // Integers must stay numbers, not booleans.
        XCTAssertEqual(map["minimum"], .double(0))
        XCTAssertEqual(map["default"], .double(1))
        XCTAssertEqual(map["maxItems"], .double(1))
        XCTAssertEqual(map["count"], .double(5))
        XCTAssertEqual(map["ratio"], .double(0.5))

        // Genuine JSON booleans must stay booleans.
        XCTAssertEqual(map["flag"], .bool(true))
        XCTAssertEqual(map["off"], .bool(false))
    }
}
