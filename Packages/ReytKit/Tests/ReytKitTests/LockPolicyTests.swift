import Testing

@testable import ReytKit

struct LockPolicyTests {
    @Test func coldLaunchLocks() {
        #expect(LockPolicy.launchState == .locked)
        #expect(LockPolicy.next(.unlocked, .coldLaunch) == .locked)
    }

    @Test func backgroundLocksFromEveryUsableState() {
        for state in [LockState.unlocked, .locked, .authenticating] {
            #expect(LockPolicy.next(state, .enteredBackground) == .locked)
        }
    }

    @Test func backgroundKeepsUnavailable() {
        #expect(LockPolicy.next(.unavailable, .enteredBackground) == .unavailable)
    }

    @Test func inactiveNeverChangesState() {
        for state in [LockState.unlocked, .locked, .authenticating, .unavailable] {
            #expect(LockPolicy.next(state, .enteredInactive) == state)
        }
    }

    @Test func successUnlocks() {
        #expect(LockPolicy.next(.authenticating, .authSucceeded) == .unlocked)
    }

    @Test func cancelStaysLocked() {
        #expect(LockPolicy.next(.authenticating, .authFailed) == .locked)
    }

    @Test func noPasscodeIsUnavailable() {
        #expect(LockPolicy.next(.authenticating, .passcodeNotSet) == .unavailable)
        #expect(LockPolicy.next(.unavailable, .passcodeAvailable) == .locked)
    }

    @Test func secondRequestWhileInFlightIsIgnored() {
        #expect(LockPolicy.next(.authenticating, .authRequested) == .authenticating)
        #expect(LockPolicy.next(.locked, .authRequested) == .authenticating)
    }

    @Test func staleResultsDoNotUnlock() {
        // a result arriving after the app was backgrounded (state already .locked) must not unlock.
        #expect(LockPolicy.next(.locked, .authSucceeded) == .locked)
        #expect(LockPolicy.next(.unlocked, .authFailed) == .unlocked)
    }
}
