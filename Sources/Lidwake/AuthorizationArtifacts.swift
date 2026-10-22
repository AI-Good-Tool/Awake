import Foundation

enum AuthorizationArtifacts {
    // Stable upgrade identifiers: reuse existing permission and boot-reset artifacts.
    // Renaming these would strand Lidwake's privileged files on installed systems.
    static let sudoersPath = "/etc/sudoers.d/lidwake"
    static let bootResetLabel = "com.local.lidwake.sleep-reset"
    static let bootResetPlistPath = "/Library/LaunchDaemons/\(bootResetLabel).plist"
    static let bootResetArguments = ["/usr/bin/pmset", "-a", "disablesleep", "0"]
    static let passwordlessPMSetArguments = [
        ["/usr/bin/pmset", "-a", "disablesleep", "0"],
        ["/usr/bin/pmset", "-a", "disablesleep", "1"]
    ]
    static let safeInstallationMoveCommands = [
        "/bin/mv \"$daemon_tmp\" '\(bootResetPlistPath)'",
        "/bin/mv \"$sudoers_tmp\" '\(sudoersPath)'"
    ]

    static func requiresInstallation(toEnable enabled: Bool, artifactsInstalled: Bool) -> Bool {
        enabled && !artifactsInstalled
    }

    static var bootResetPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(bootResetLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/pmset</string>
                <string>-a</string>
                <string>disablesleep</string>
                <string>0</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Background</string>
        </dict>
        </plist>
        """
    }

    static func areInstalled(fileManager: FileManager = .default) -> Bool {
        guard hasExpectedMetadata(
            atPath: sudoersPath,
            permissions: 0o440,
            fileManager: fileManager
        ) && hasExpectedMetadata(
            atPath: bootResetPlistPath,
            permissions: 0o644,
            fileManager: fileManager
        ), bootResetPlistIsValid(fileManager.contents(atPath: bootResetPlistPath)) else {
            return false
        }
        return passwordlessPMSetRulesAreUsable()
    }

    static func bootResetPlistIsValid(_ data: Data?) -> Bool {
        guard let data,
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = propertyList as? [String: Any],
              dictionary["Label"] as? String == bootResetLabel,
              dictionary["ProgramArguments"] as? [String] == bootResetArguments,
              dictionary["RunAtLoad"] as? Bool == true else {
            return false
        }
        return true
    }

    static func sudoLongListConfirmsExpectedRule(_ output: String, command: String) -> Bool {
        let blocks = output.components(separatedBy: "Sudoers entry:").dropFirst()
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            guard let source = lines.first?.trimmingCharacters(in: .whitespaces),
                  source.hasSuffix(sudoersPath) else {
                continue
            }
            let normalized = block
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            if normalized.contains("Options: !authenticate"),
               normalized.contains("Matched: \(command)") {
                return true
            }
        }
        return false
    }

    private static func passwordlessPMSetRulesAreUsable() -> Bool {
        for arguments in passwordlessPMSetArguments {
            do {
                let result = try ProcessRunner.run(
                    executable: "/usr/bin/sudo",
                    arguments: ["-n", "-ll"] + arguments,
                    timeout: 5
                )
                let command = arguments.joined(separator: " ")
                guard result.terminationStatus == 0,
                      sudoLongListConfirmsExpectedRule(result.output, command: command) else {
                    return false
                }
            } catch {
                AppLog.write("failed to validate passwordless pmset rule: \(error.localizedDescription)")
                return false
            }
        }
        return true
    }

    private static func hasExpectedMetadata(
        atPath path: String,
        permissions: Int,
        fileManager: FileManager
    ) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              (attributes[.groupOwnerAccountID] as? NSNumber)?.intValue == 0,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == permissions else {
            return false
        }
        return true
    }
}
