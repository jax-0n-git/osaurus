//
//  ToolsUninstall.swift
//  osaurus
//
//  Command to uninstall a plugin by ID, folder name, or path.
//

import Foundation

public struct ToolsUninstall {
    public static func execute(args: [String]) {
        guard let target = args.first, !target.isEmpty else {
            fputs("Usage: osaurus tools uninstall <plugin_id|folder|path>\n", stderr)
            exit(EXIT_FAILURE)
        }
        let fm = FileManager.default
        let root = Configuration.toolsRootDirectory()
        guard let dir = resolveTargetDirectory(target, root: root, fileManager: fm) else {
            fputs("Could not locate installed plugin for '\(target)'\n", stderr)
            exit(EXIT_FAILURE)
        }
        do {
            try fm.removeItem(at: dir)
            print("Uninstalled \(dir.lastPathComponent)")
        } catch {
            fputs("Failed to uninstall: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
        // Notify app to reload
        AppControl.postDistributedNotification(name: "com.dinoki.osaurus.control.toolsReload", userInfo: [:])
        exit(EXIT_SUCCESS)
    }

    /// `true` when `target` is unambiguously a filesystem path (not a bare
    /// plugin id / folder name). Mirrors ToolsInstall's path convention.
    static func looksLikeExplicitPath(_ target: String) -> Bool {
        target.hasPrefix("/") || target.hasPrefix("./") || target.hasPrefix("../")
            || target.hasPrefix("~") || target.contains("/")
    }

    /// Resolve the directory to remove for `target`, checking sources in order:
    /// (1) an explicit filesystem path — only when `target` actually looks like a
    /// path, so a bare name like `foo` can never resolve to a same-named
    /// directory in the current working directory; (2) a folder directly under
    /// the tools root (its name is the plugin id); (3) a plugin whose
    /// `receipt.json` plugin_id (or directory name) matches `target`.
    static func resolveTargetDirectory(
        _ target: String,
        root: URL,
        fileManager fm: FileManager = .default
    ) -> URL? {
        var isDir: ObjCBool = false

        // (1) Explicit path mode — gated so a bare plugin name is never treated
        // as a current-working-directory path (which would delete the wrong dir).
        if looksLikeExplicitPath(target) {
            let tURL = URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
            if fm.fileExists(atPath: tURL.path, isDirectory: &isDir), isDir.boolValue {
                return tURL
            }
        }

        // (2) Direct folder under the Tools root (directory name is plugin_id).
        let candidate = root.appendingPathComponent(target, isDirectory: true)
        if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
            return candidate
        }

        // (3) Match by plugin_id from receipt.json, then by directory name.
        guard let contents = try? fm.contentsOfDirectory(atPath: root.path) else { return nil }
        for entry in contents {
            if entry.hasPrefix(".") { continue }
            let pluginDir = root.appendingPathComponent(entry, isDirectory: true)

            let currentLink = pluginDir.appendingPathComponent("current")
            if let versionName = try? fm.destinationOfSymbolicLink(atPath: currentLink.path) {
                let receiptURL =
                    pluginDir
                    .appendingPathComponent(versionName, isDirectory: true)
                    .appendingPathComponent("receipt.json")
                if let data = try? Data(contentsOf: receiptURL),
                    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                {
                    let pluginId = (obj["plugin_id"] as? String) ?? ""
                    if pluginId == target { return pluginDir }
                }
            }

            // Also match by directory name (which should be the plugin_id).
            if entry == target { return pluginDir }
        }
        return nil
    }
}
