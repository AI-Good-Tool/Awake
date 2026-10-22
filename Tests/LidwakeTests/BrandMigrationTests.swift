import Foundation
import Testing
@testable import Lidwake

struct BrandMigrationTests {
    @MainActor
    @Test func renamePreservesSettingsAndSleepOwnershipWithoutOverwritingNewPreferences() throws {
        let destination = "awake-migration-test.\(UUID().uuidString)"
        let legacy = "lidwake-migration-test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: destination))
        defer {
            defaults.removePersistentDomain(forName: destination)
            defaults.removePersistentDomain(forName: legacy)
        }
        let schedules = Data("saved-schedules".utf8)
        defaults.setPersistentDomain([
            "settings.schedules": schedules,
            "settings.forceClosedLidWake": true,
            "settings.lowBatteryThreshold": 20,
            "runtime.systemSleepOverrideApplied": true,
            "runtime.systemSleepOverrideManaged": true,
            "runtime.systemSleepOverrideManagedVersion": 2,
            "runtime.quickPaused": true,
            "diagnostics.wasRunning": true,
            "diagnostics.crashRecords": Data("records".utf8),
            "com.local.lidwake.lockfd": 99
        ], forName: legacy)
        defaults.setPersistentDomain([
            "settings.lowBatteryThreshold": 35,
            "settings.forceClosedLidWake": false
        ], forName: destination)

        Storage.migrateLegacyPreferences(defaults: defaults, destinationDomain: destination, legacyDomain: legacy)
        #expect(defaults.data(forKey: "settings.schedules") == schedules)
        #expect(defaults.integer(forKey: "settings.lowBatteryThreshold") == 35)
        #expect(!defaults.bool(forKey: "settings.forceClosedLidWake"))
        #expect(defaults.bool(forKey: "runtime.systemSleepOverrideManaged"))
        #expect(defaults.bool(forKey: "runtime.systemSleepOverrideApplied"))
        #expect(defaults.integer(forKey: "runtime.systemSleepOverrideManagedVersion") == 2)
        #expect(defaults.bool(forKey: "runtime.quickPaused"))
        #expect(defaults.data(forKey: "diagnostics.crashRecords") == Data("records".utf8))
        #expect(defaults.object(forKey: "diagnostics.wasRunning") == nil)
        #expect(defaults.object(forKey: "com.local.lidwake.lockfd") == nil)
        #expect(defaults.persistentDomain(forName: legacy)?["settings.schedules"] as? Data == schedules)

        // A subsequent launch must not re-import keys deliberately removed in Awake.
        defaults.removeObject(forKey: "settings.schedules")
        Storage.migrateLegacyPreferences(defaults: defaults, destinationDomain: destination, legacyDomain: legacy)
        #expect(defaults.object(forKey: "settings.schedules") == nil)
    }

    @MainActor
    @Test func freshInstallDoesNotInventLegacyRuntimeOwnership() throws {
        let destination = "awake-fresh-test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: destination))
        defer { defaults.removePersistentDomain(forName: destination) }
        Storage.migrateLegacyPreferences(
            defaults: defaults,
            destinationDomain: destination,
            legacyDomain: "absent.\(UUID().uuidString)"
        )
        #expect(!defaults.bool(forKey: "runtime.systemSleepOverrideManaged"))
        #expect(!defaults.bool(forKey: "settings.forceClosedLidWake"))
    }
}
