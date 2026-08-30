import Foundation

/// Reads current ChatGPT-backed Codex limits through the official Codex
/// app-server account API. Rollout JSONL files are event logs and can contain
/// placeholder 0/0 rate-limit fields, so they are not a reliable account-wide
/// usage source.
enum CodexUsageEngine {
    struct Snapshot {
        let primaryPercent: Double
        let primaryResetsLabel: String
        let secondaryPercent: Double?
        let secondaryResetsLabel: String?
        let planType: String?
    }

    private struct AccountWindow {
        let percent: Double
        let durationMinutes: Double
        let resetsAt: Double?
    }

    /// Parses the official Codex app-server `account/rateLimits/read`
    /// response. Kept internal so the external response contract can be
    /// verified without starting a credential-bearing subprocess in tests.
    static func parseRateLimitsResponse(_ data: Data, now: Date) -> Snapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any]
        else { return nil }

        var limits = result["rateLimits"] as? [String: Any]
        if limits == nil,
           let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            limits = byID["codex"] as? [String: Any]
        }
        guard let limits else { return nil }

        let windows = ["primary", "secondary"]
            .compactMap { accountWindow(limits[$0]) }
            .sorted { $0.durationMinutes < $1.durationMinutes }
        guard let first = windows.first else { return nil }

        let session: AccountWindow?
        let weekly: AccountWindow?
        if windows.count > 1 {
            session = first
            weekly = windows.last
        } else if first.durationMinutes >= 24 * 60 {
            session = nil
            weekly = first
        } else {
            session = first
            weekly = nil
        }

        return Snapshot(
            primaryPercent: session?.percent ?? 0,
            primaryResetsLabel: resetLabel(resetsAt: session?.resetsAt, now: now),
            secondaryPercent: weekly?.percent,
            secondaryResetsLabel: weekly.map { resetLabel(resetsAt: $0.resetsAt, now: now) },
            planType: limits["planType"] as? String
        )
    }

    static func computeSnapshot() -> Snapshot? {
        guard let response = fetchRateLimitsResponse() else { return nil }
        return parseRateLimitsResponse(response, now: Date())
    }

    private static func accountWindow(_ value: Any?) -> AccountWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = (object["usedPercent"] as? NSNumber)?.doubleValue,
              let durationMinutes = (object["windowDurationMins"] as? NSNumber)?.doubleValue
        else { return nil }
        return AccountWindow(
            percent: usedPercent / 100,
            durationMinutes: durationMinutes,
            resetsAt: (object["resetsAt"] as? NSNumber)?.doubleValue
        )
    }

    /// Starts the locally installed official app-server, performs only the
    /// initialization handshake and one read-only account request, then stops
    /// it. The subprocess owns ChatGPT authentication; Throttle never reads or
    /// copies Codex tokens.
    private static func fetchRateLimitsResponse() -> Data? {
        guard let executable = codexExecutableURL() else { return nil }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let completed = DispatchSemaphore(value: 0)
        let completionLock = NSLock()
        let responseLock = NSLock()
        var didComplete = false
        var response: Data?
        var buffer = Data()

        func completeOnce() {
            completionLock.lock()
            let shouldSignal = !didComplete
            didComplete = true
            completionLock.unlock()
            if shouldSignal { completed.signal() }
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                completeOnce()
                return
            }

            var foundResponse = false
            responseLock.lock()
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (object["id"] as? NSNumber)?.intValue == 1
                else { continue }
                if object["result"] is [String: Any] { response = line }
                foundResponse = true
                break
            }
            responseLock.unlock()
            if foundResponse { completeOnce() }
        }
        process.terminationHandler = { _ in completeOnce() }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "throttle",
                        "title": "Throttle",
                        "version": "1.0",
                    ],
                ],
            ],
            ["method": "initialized", "params": [:]],
            ["method": "account/rateLimits/read", "id": 1],
        ]
        var requestData = Data()
        for message in messages {
            guard let line = try? JSONSerialization.data(withJSONObject: message) else {
                process.terminate()
                output.fileHandleForReading.readabilityHandler = nil
                return nil
            }
            requestData.append(line)
            requestData.append(0x0A)
        }
        input.fileHandleForWriting.write(requestData)

        _ = completed.wait(timeout: .now() + 15)
        output.fileHandleForReading.readabilityHandler = nil
        input.fileHandleForWriting.closeFile()
        if process.isRunning { process.terminate() }

        responseLock.lock()
        let captured = response
        responseLock.unlock()
        return captured
    }

    private static func codexExecutableURL() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            home + "/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]

        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates.append(contentsOf: environmentPath.split(separator: ":").map { String($0) + "/codex" })

        let nvmRoot = home + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) {
            candidates.append(contentsOf: versions.sorted {
                $0.compare($1, options: .numeric) == .orderedDescending
            }.map { nvmRoot + "/" + $0 + "/bin/codex" })
        }

        return candidates.first(where: fm.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    private static func resetLabel(resetsAt: Double?, now: Date) -> String {
        guard let resetsAt else { return "unknown" }
        let resetDate = Date(timeIntervalSince1970: resetsAt)
        let interval = resetDate.timeIntervalSince(now)
        if interval <= 0 { return "now" }
        let hours = Int(interval / 3600)
        if hours >= 24 {
            return "in \(hours / 24)d"
        } else if hours >= 1 {
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(Int(interval / 60)) min"
        }
    }
}
