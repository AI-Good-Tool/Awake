import Testing
@testable import Lidwake

struct SystemSleepOverrideTests {
    @Test func parserRecognizesEnabledGlobalState() {
        let state = SystemSleepStateParser.state(
            globalOutput: "SleepDisabled\t1",
            customOutput: nil
        )

        #expect(state == .enabled)
    }

    @Test func parserRecognizesDisabledStateWhenBothReadsSucceed() {
        let state = SystemSleepStateParser.state(
            globalOutput: "SleepDisabled\t0",
            customOutput: "disablesleep\t0"
        )

        #expect(state == .disabled)
    }

    @Test func parserPreservesUnknownWhenAReadFails() {
        let state = SystemSleepStateParser.state(
            globalOutput: nil,
            customOutput: "disablesleep\t0"
        )

        #expect(state == .unknown)
    }

    @Test func parserPreservesUnknownWhenOutputFormatIsUnrecognized() {
        let state = SystemSleepStateParser.state(
            globalOutput: "System sleep override: off",
            customOutput: "No matching power setting"
        )

        #expect(state == .unknown)
    }

    @Test func parserTreatsAnyEnabledCustomProfileAsEnabled() {
        let state = SystemSleepStateParser.state(
            globalOutput: "SleepDisabled\t0",
            customOutput: "Battery Power:\n disablesleep 0\nAC Power:\n disablesleep 1"
        )

        #expect(state == .enabled)
    }

    @Test func watchdogRetryDelayUsesBoundedExponentialBackoff() {
        #expect(SleepOverrideWatchdog.retryDelay(after: 1) == 1)
        #expect(SleepOverrideWatchdog.retryDelay(after: 2) == 2)
        #expect(SleepOverrideWatchdog.retryDelay(after: 4) == 8)
        #expect(SleepOverrideWatchdog.retryDelay(after: 8) == 8)
    }
}
