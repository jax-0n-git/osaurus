//
//  ServerSupervisor.swift
//  osaurus
//
//  Keeps the Osaurus server alive across app quit/crash. Periodically probes
//  /health and re-launches the app when it is down. Intended to run as a
//  long-lived process under a launchd KeepAlive LaunchAgent, so the server
//  (and the in-app scheduler that only ticks while the app is running)
//  survives quit, crash, logout, and reboot.
//

import Foundation

/// A long-running keep-alive loop for the Osaurus server.
///
/// On each iteration it probes `/health`; if the server is down it asks for it
/// to be brought back up. All collaborators are injected so the loop logic is
/// unit-testable without a real server, app, or sleep.
public struct ServerSupervisor: Sendable {
    /// Port to probe for health.
    public let port: Int
    /// Seconds between health probes.
    public let probeInterval: TimeInterval
    /// Number of iterations to run before returning. `nil` runs forever
    /// (production); a finite value bounds the loop for tests.
    public let maxIterations: Int?

    /// Probe the server's health. Injectable for testing.
    let healthCheck: @Sendable (Int) async -> Bool
    /// Bring the server back up (launch app + request serve). Injectable for testing.
    let ensureServing: @Sendable () async -> Void
    /// Sleep between probes. Injectable for testing.
    let sleep: @Sendable (TimeInterval) async -> Void
    /// Emit a log line. Injectable for testing.
    let log: @Sendable (String) -> Void

    public init(
        port: Int,
        probeInterval: TimeInterval = 15.0,
        maxIterations: Int? = nil,
        healthCheck: @escaping @Sendable (Int) async -> Bool = {
            await ServerControl.checkHealth(port: $0)
        },
        ensureServing: @escaping @Sendable () async -> Void,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = {
            try? await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000))
        },
        log: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.port = port
        self.probeInterval = probeInterval
        self.maxIterations = maxIterations
        self.healthCheck = healthCheck
        self.ensureServing = ensureServing
        self.sleep = sleep
        self.log = log
    }

    /// Run the supervise loop. Returns only after `maxIterations` iterations;
    /// in production (`maxIterations == nil`) it never returns.
    public func run() async {
        log("supervising osaurus server on port \(port) (probe every \(Int(probeInterval))s)")
        var wasHealthy = true
        var iteration = 0
        while maxIterations.map({ iteration < $0 }) ?? true {
            let healthy = await healthCheck(port)
            if !healthy {
                log("server on port \(port) is not responding — relaunching")
                await ensureServing()
            } else if !wasHealthy {
                log("server on port \(port) is back up")
            }
            wasHealthy = healthy
            iteration += 1
            await sleep(probeInterval)
        }
    }
}
