//
//  PalaceToolsIntegrationTests.swift
//  osaurusTests
//
//  End-to-end tool round-trip against a temp OsaurusPaths root:
//  enable palace.json → palace_add_drawer → palace_search → palace_get_drawer,
//  plus the disabled-flag envelope and the composer strip set.
//  Uses embeddingBackend "none" so no model download is needed in CI —
//  the search path exercised here is FTS5.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite(.serialized)
struct PalaceToolsIntegrationTests {

    /// Runs `body` against an isolated OsaurusPaths root with palace
    /// enabled (embeddingBackend "none") and a fresh PalaceDatabase.shared
    /// state. `overrideRoot` is process-global — take the cross-suite lock.
    private func withEnabledPalace(_ body: @Sendable () async throws -> Void) async throws {
        try await StoragePathsTestLock.shared.run {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "palace-integration-\(UUID().uuidString)",
                    isDirectory: true
                )
            let previousRoot = OsaurusPaths.overrideRoot
            OsaurusPaths.overrideRoot = root
            PalaceConfigurationStore.invalidateCache()
            var config = PalaceConfiguration()
            config.enabled = true
            config.embeddingBackend = "none"
            PalaceConfigurationStore.save(config)
            defer {
                PalaceDatabase.shared.close()
                OsaurusPaths.overrideRoot = previousRoot
                PalaceConfigurationStore.invalidateCache()
                try? FileManager.default.removeItem(at: root)
            }
            try await body()
        }
    }

    private func decodeEnvelope(_ json: String) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return (obj as? [String: Any]) ?? [:]
    }

    @Test func disabled_flag_returns_unavailable_and_creates_nothing() async throws {
        try await StoragePathsTestLock.shared.run {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("palace-disabled-\(UUID().uuidString)", isDirectory: true)
            let previousRoot = OsaurusPaths.overrideRoot
            OsaurusPaths.overrideRoot = root
            PalaceConfigurationStore.invalidateCache()
            defer {
                OsaurusPaths.overrideRoot = previousRoot
                PalaceConfigurationStore.invalidateCache()
                try? FileManager.default.removeItem(at: root)
            }

            let result = try await PalaceAddDrawerTool().execute(
                argumentsJSON: #"{"content": "should not land"}"#
            )
            let envelope = try decodeEnvelope(result)
            #expect(envelope["ok"] as? Bool == false)
            // Nothing was created on disk — a disabled palace does zero work.
            #expect(
                !FileManager.default.fileExists(atPath: OsaurusPaths.palaceDatabaseFile().path)
            )
        }
    }

    @Test func add_search_get_roundTrip() async throws {
        try await withEnabledPalace {
            let addResult = try await PalaceAddDrawerTool().execute(
                argumentsJSON:
                    #"{"content": "The verbatim GraphQL federation decision from March.", "wing": "test_project", "room": "decisions"}"#
            )
            let addEnvelope = try decodeEnvelope(addResult)
            #expect(addEnvelope["ok"] as? Bool == true)
            let drawerId =
                ((addEnvelope["result"] as? [String: Any])?["drawer_id"] as? String) ?? ""
            #expect(!drawerId.isEmpty)

            // Search finds it (FTS path), scoped and unscoped.
            for argsJSON in [
                #"{"query": "graphql federation"}"#,
                #"{"query": "graphql federation", "wing": "test_project", "room": "decisions"}"#,
            ] {
                let searchResult = try await PalaceSearchTool().execute(argumentsJSON: argsJSON)
                let searchEnvelope = try decodeEnvelope(searchResult)
                #expect(searchEnvelope["ok"] as? Bool == true)
                let hits =
                    ((searchEnvelope["result"] as? [String: Any])?["hits"] as? [[String: Any]])
                    ?? []
                #expect(hits.count == 1)
                #expect(hits.first?["drawer_id"] as? String == drawerId)
            }

            // Get returns the full verbatim content.
            let getResult = try await PalaceGetDrawerTool().execute(
                argumentsJSON: #"{"drawer_id": "\#(drawerId)"}"#
            )
            let getEnvelope = try decodeEnvelope(getResult)
            #expect(getEnvelope["ok"] as? Bool == true)
            let content = ((getEnvelope["result"] as? [String: Any])?["content"] as? String) ?? ""
            #expect(content == "The verbatim GraphQL federation decision from March.")

            // Dedup: identical re-add returns the same drawer, deduped=true.
            let dupResult = try await PalaceAddDrawerTool().execute(
                argumentsJSON:
                    #"{"content": "The verbatim GraphQL federation decision from March.", "wing": "test_project", "room": "decisions"}"#
            )
            let dupEnvelope = try decodeEnvelope(dupResult)
            let dup = (dupEnvelope["result"] as? [String: Any]) ?? [:]
            #expect(dup["deduped"] as? Bool == true)
            #expect(dup["drawer_id"] as? String == drawerId)

            // Status reflects one drawer.
            let statusResult = try await PalaceStatusTool().execute(argumentsJSON: "{}")
            let statusEnvelope = try decodeEnvelope(statusResult)
            let status = (statusEnvelope["result"] as? [String: Any]) ?? [:]
            #expect(status["drawers"] as? Int == 1)
            #expect(status["wings"] as? Int == 1)
        }
    }

    @Test func update_delete_roundTrip() async throws {
        try await withEnabledPalace {
            let addResult = try await PalaceAddDrawerTool().execute(
                argumentsJSON: #"{"content": "original wording"}"#
            )
            let drawerId =
                (((try decodeEnvelope(addResult))["result"] as? [String: Any])?["drawer_id"]
                    as? String) ?? ""
            #expect(!drawerId.isEmpty)

            let updateResult = try await PalaceUpdateDrawerTool().execute(
                argumentsJSON: #"{"drawer_id": "\#(drawerId)", "content": "revised wording"}"#
            )
            #expect((try decodeEnvelope(updateResult))["ok"] as? Bool == true)

            let getResult = try await PalaceGetDrawerTool().execute(
                argumentsJSON: #"{"drawer_id": "\#(drawerId)"}"#
            )
            let content =
                (((try decodeEnvelope(getResult))["result"] as? [String: Any])?["content"]
                    as? String) ?? ""
            #expect(content == "revised wording")

            let deleteResult = try await PalaceDeleteDrawerTool().execute(
                argumentsJSON: #"{"drawer_id": "\#(drawerId)"}"#
            )
            #expect((try decodeEnvelope(deleteResult))["ok"] as? Bool == true)

            // Second delete → not_found envelope.
            let secondDelete = try await PalaceDeleteDrawerTool().execute(
                argumentsJSON: #"{"drawer_id": "\#(drawerId)"}"#
            )
            #expect((try decodeEnvelope(secondDelete))["ok"] as? Bool == false)
        }
    }

    @Test func composer_strip_set_matches_registered_tool_names() {
        // The strip set and the registered tool names must stay in lockstep;
        // a palace tool missing from `palaceToolNames` would leak into the
        // schema while the flag is off.
        let registered: Set<String> = [
            PalaceStatusTool().name, PalaceSearchTool().name, PalaceAddDrawerTool().name,
            PalaceGetDrawerTool().name, PalaceUpdateDrawerTool().name,
            PalaceDeleteDrawerTool().name, PalaceListWingsTool().name,
            PalaceListRoomsTool().name, PalaceListDrawersTool().name,
        ]
        #expect(registered == SystemPromptComposer.palaceToolNames)
    }

    /// No-Memory-v2-regression guard: with palace enabled and used, the
    /// memory database file is untouched (Palace never opens or writes it).
    @Test func palace_usage_does_not_touch_memory_database() async throws {
        try await withEnabledPalace {
            _ = try await PalaceAddDrawerTool().execute(
                argumentsJSON: #"{"content": "palace-only write"}"#
            )
            #expect(FileManager.default.fileExists(atPath: OsaurusPaths.palaceDatabaseFile().path))
            #expect(
                !FileManager.default.fileExists(atPath: OsaurusPaths.memoryDatabaseFile().path)
            )
        }
    }
}
