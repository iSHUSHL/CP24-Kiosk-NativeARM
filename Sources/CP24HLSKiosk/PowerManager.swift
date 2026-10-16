import Foundation
import IOKit.pwr_mgt

final class PowerManager {
    static let shared = PowerManager()

    private var systemSleepAssertion: IOPMAssertionID = 0
    private var displaySleepAssertion: IOPMAssertionID = 0

    private init() {}

    func setSleepDisabled(_ disabled: Bool) {
        if disabled {
            acquireAssertions()
        } else {
            releaseAssertions()
        }
    }

    deinit {
        releaseAssertions()
    }

    private func acquireAssertions() {
        guard systemSleepAssertion == 0 || displaySleepAssertion == 0 else { return }

        if systemSleepAssertion == 0 {
            let reason = "CP24 HLS Kiosk is playing a live stream" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &systemSleepAssertion
            )
            if result == kIOReturnSuccess {
                StreamHealthLog.append("Sleep guard enabled: system sleep disabled")
            } else {
                StreamHealthLog.append("Sleep guard failed: system sleep assertion error \(result)")
            }
        }

        if displaySleepAssertion == 0 {
            let reason = "CP24 HLS Kiosk is showing a live stream" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &displaySleepAssertion
            )
            if result == kIOReturnSuccess {
                StreamHealthLog.append("Sleep guard enabled: display sleep disabled")
            } else {
                StreamHealthLog.append("Sleep guard failed: display sleep assertion error \(result)")
            }
        }
    }

    private func releaseAssertions() {
        if systemSleepAssertion != 0 {
            IOPMAssertionRelease(systemSleepAssertion)
            systemSleepAssertion = 0
            StreamHealthLog.append("Sleep guard released: system sleep allowed")
        }

        if displaySleepAssertion != 0 {
            IOPMAssertionRelease(displaySleepAssertion)
            displaySleepAssertion = 0
            StreamHealthLog.append("Sleep guard released: display sleep allowed")
        }
    }
}
