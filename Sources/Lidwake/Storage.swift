import Foundation

@MainActor
enum Storage {
    /// Copy only persistent app data once; never overwrite newer Awake preferences.
    static func migrateLegacyPreferences(
        defaults: UserDefaults = .standard,
        destinationDomain: String = Brand.bundleIdentifier,
        legacyDomain: String = Brand.legacyBundleIdentifier
    ) {
        let migrationKey = "migration.lidwake.v1"
        var destination = defaults.persistentDomain(forName: destinationDomain) ?? [:]
        guard destination[migrationKey] as? Bool != true else { return }
        let legacy = defaults.persistentDomain(forName: legacyDomain) ?? [:]
        for (key, value) in legacy where destination[key] == nil {
            // Runtime ownership must survive a rename so closed-lid protection can be released.
            if key.hasPrefix("settings.") || key.hasPrefix("runtime.") || key == "diagnostics.crashRecords" {
                destination[key] = value
            }
        }
        destination[migrationKey] = true
        defaults.setPersistentDomain(destination, forName: destinationDomain)
    }

    static func load<Value: Decodable>(_ type: Value.Type, key: String, fallback: Value) -> Value {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: key) else { return fallback }
        return (try? JSONDecoder().decode(type, from: data)) ?? fallback
    }

    static func save<Value: Encodable>(_ value: Value, key: String) {
        let defaults = UserDefaults.standard
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
