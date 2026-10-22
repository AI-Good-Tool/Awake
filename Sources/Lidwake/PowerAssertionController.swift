import Foundation
import IOKit.pwr_mgt

final class PowerAssertionController {
    private var noDisplaySleepID = IOPMAssertionID(0)
    private var noIdleSleepID = IOPMAssertionID(0)

    func apply(mode: KeepAwakeMode, reason: String) {
        setAssertion(
            enabled: mode.keepsDisplayAwake,
            type: kIOPMAssertionTypeNoDisplaySleep as CFString,
            currentID: &noDisplaySleepID,
            reason: reason
        )

        setAssertion(
            enabled: mode.keepsSystemAwake,
            type: kIOPMAssertionTypeNoIdleSleep as CFString,
            currentID: &noIdleSleepID,
            reason: reason
        )
    }

    func releaseAll() {
        release(id: &noDisplaySleepID)
        release(id: &noIdleSleepID)
    }

    private func setAssertion(
        enabled: Bool,
        type: CFString,
        currentID: inout IOPMAssertionID,
        reason: String
    ) {
        if enabled {
            guard currentID == 0 else { return }
            var newID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &newID
            )
            if result == kIOReturnSuccess {
                currentID = newID
            }
        } else {
            release(id: &currentID)
        }
    }

    private func release(id: inout IOPMAssertionID) {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }
}
