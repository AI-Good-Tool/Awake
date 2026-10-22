import AppKit
import Darwin

if SleepOverrideWatchdog.runIfRequested(arguments: CommandLine.arguments) {
    exit(EXIT_SUCCESS)
}
if AppSupervisor.runIfRequested(arguments: CommandLine.arguments) {
    exit(EXIT_SUCCESS)
}
AppRecoveryHandshake.signalStartedIfRequested(arguments: CommandLine.arguments)

let application = NSApplication.shared
let delegate = AppDelegate()

application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
