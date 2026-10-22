import AppKit
import Foundation

@MainActor
final class CrashDiagnostics {
    static let shared = CrashDiagnostics()

    private let runningKey = "diagnostics.wasRunning"
    private let recordsKey = "diagnostics.crashRecords"

    private init() {}

    var records: [CrashRecord] {
        get { Storage.load([CrashRecord].self, key: recordsKey, fallback: []) }
        set { Storage.save(newValue, key: recordsKey) }
    }

    @discardableResult
    func markLaunch() -> Bool {
        let detectedUnexpectedExit = UserDefaults.standard.bool(forKey: runningKey)
        if detectedUnexpectedExit {
            var current = records
            current.insert(
                CrashRecord(
                    detectedAt: Date(),
                    note: "检测到上次运行未正常退出。可能是崩溃、强制退出或系统关机。"
                ),
                at: 0
            )
            records = Array(current.prefix(20))
        }

        UserDefaults.standard.set(true, forKey: runningKey)
        return detectedUnexpectedExit
    }

    func markCleanExit() {
        UserDefaults.standard.set(false, forKey: runningKey)
    }

    func clearRecords() {
        records = []
    }

    func export(status: RuntimeStatus) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let payload = DiagnosticsPayload(
            generatedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版",
            runtimeStatus: status,
            crashRecords: records
        )

        guard let data = try? encoder.encode(payload) else { return nil }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("\(Brand.executableName)-Diagnostics.json")

        do {
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return url
        } catch {
            return nil
        }
    }
}

private struct DiagnosticsPayload: Codable {
    var generatedAt: Date
    var appVersion: String
    var runtimeStatus: RuntimeStatusSnapshot
    var crashRecords: [CrashRecord]

    init(generatedAt: Date, appVersion: String, runtimeStatus: RuntimeStatus, crashRecords: [CrashRecord]) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.runtimeStatus = RuntimeStatusSnapshot(status: runtimeStatus)
        self.crashRecords = crashRecords
    }
}

private struct RuntimeStatusSnapshot: Codable {
    var effectiveMode: String
    var reason: String
    var activeAppName: String
    var activeAppBundleID: String
    var power: PowerSnapshot

    init(status: RuntimeStatus) {
        effectiveMode = status.effectiveMode.title
        reason = status.reason
        activeAppName = status.activeAppName
        activeAppBundleID = status.activeAppBundleID
        power = status.power
    }
}
