import Testing
@testable import ModweaveApp

@Suite("Agent status resolution")
struct AgentStateTests {
    static let ready = AgentInputs(userEnabled: true, sessionActive: true, permissionsGranted: true, rulesLoaded: true, safeMode: false)

    @Test func runsOnlyWhenEveryInputAllowsIt() {
        #expect(AgentStatus.resolve(Self.ready) == .active)
        #expect(AgentStatus.resolve(Self.ready).shouldRunTap)
    }

    @Test func inactiveSessionWinsOverEverything() {
        var inputs = Self.ready
        inputs.sessionActive = false
        inputs.permissionsGranted = false
        inputs.safeMode = true
        #expect(AgentStatus.resolve(inputs) == .pausedInactiveSession)
        #expect(!AgentStatus.resolve(inputs).shouldRunTap)
    }

    @Test func switchingSessionsRestoresActiveWithoutUserAction() {
        var inputs = Self.ready
        inputs.sessionActive = false
        #expect(AgentStatus.resolve(inputs) == .pausedInactiveSession)
        inputs.sessionActive = true
        #expect(AgentStatus.resolve(inputs) == .active)
    }

    @Test func userPauseSurvivesSessionSwitch() {
        var inputs = Self.ready
        inputs.userEnabled = false
        inputs.sessionActive = false
        inputs.sessionActive = true
        #expect(AgentStatus.resolve(inputs) == .pausedByUser)
    }

    @Test func eachMissingInputPausesWithItsReason() {
        var noPermission = Self.ready
        noPermission.permissionsGranted = false
        #expect(AgentStatus.resolve(noPermission) == .needsPermission)

        var noRules = Self.ready
        noRules.rulesLoaded = false
        #expect(AgentStatus.resolve(noRules) == .configurationError)

        var paused = Self.ready
        paused.userEnabled = false
        #expect(AgentStatus.resolve(paused) == .pausedByUser)

        for status in [AgentStatus.needsPermission, .configurationError, .pausedByUser] {
            #expect(!status.shouldRunTap)
        }
    }

    @Test func safeModeBlocksUntilCleared() {
        var inputs = Self.ready
        inputs.safeMode = true
        #expect(AgentStatus.resolve(inputs) == .safeMode)
    }
}
