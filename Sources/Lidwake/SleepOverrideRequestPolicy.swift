import Foundation

enum SleepOverrideRequestPolicy {
    static let minimumResyncInterval: TimeInterval = 5 * 60

    static func target(forceClosedLidWake: Bool, mode: KeepAwakeMode) -> Bool {
        forceClosedLidWake && mode != .off
    }

    static func shouldSkip(
        hasPendingRequest: Bool,
        lastTarget: Bool?,
        newTarget: Bool,
        allowPrompt: Bool,
        lastSyncDate: Date?,
        now: Date
    ) -> Bool {
        guard !hasPendingRequest,
              lastTarget == newTarget,
              !allowPrompt,
              let lastSyncDate else {
            return false
        }
        return now.timeIntervalSince(lastSyncDate) < minimumResyncInterval
    }

    static func mergedAllowPrompt(
        existingTarget: Bool?,
        existingAllowPrompt: Bool?,
        newTarget: Bool,
        newAllowPrompt: Bool
    ) -> Bool {
        newAllowPrompt || (existingTarget == newTarget && existingAllowPrompt == true)
    }

    static func shouldRestartWorker(
        workerExists: Bool,
        existingTarget: Bool?,
        existingAllowPrompt: Bool?,
        newTarget: Bool,
        newAllowPrompt: Bool
    ) -> Bool {
        !workerExists
            || existingTarget != newTarget
            || (newAllowPrompt && existingAllowPrompt == false)
    }
}
