import Testing
@testable import IkeruCore

@Test("SessionEndState stores all fields")
func sessionEndStateInit() {
    let state = SessionEndState(elapsedSeconds: 120, completedCount: 3, activeItemInFlight: true)
    #expect(state.elapsedSeconds == 120)
    #expect(state.completedCount == 3)
    #expect(state.activeItemInFlight == true)
}
