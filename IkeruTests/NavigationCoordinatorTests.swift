import Testing
@testable import Ikeru

@Suite("NavigationCoordinator")
@MainActor
struct NavigationCoordinatorTests {

    @Test("Initial path is empty")
    func initialPathIsEmpty() {
        let coordinator = NavigationCoordinator()
        #expect(coordinator.path.count == 0)
    }

    @Test("Push adds to path")
    func pushAddsToPath() {
        let coordinator = NavigationCoordinator()
        coordinator.push(.home)
        #expect(coordinator.path.count == 1)
    }

    @Test("Multiple pushes increment path count")
    func multiplePushes() {
        let coordinator = NavigationCoordinator()
        coordinator.push(.home)
        coordinator.push(.studySession)
        coordinator.push(.settings)
        #expect(coordinator.path.count == 3)
    }

    @Test("Pop removes last from path")
    func popRemovesLast() {
        let coordinator = NavigationCoordinator()
        coordinator.push(.home)
        coordinator.push(.studySession)
        coordinator.pop()
        #expect(coordinator.path.count == 1)
    }

    @Test("Pop on empty path does nothing")
    func popOnEmptyPath() {
        let coordinator = NavigationCoordinator()
        coordinator.pop()
        #expect(coordinator.path.count == 0)
    }

    @Test("PopToRoot clears entire path")
    func popToRoot() {
        let coordinator = NavigationCoordinator()
        coordinator.push(.home)
        coordinator.push(.studySession)
        coordinator.push(.settings)
        coordinator.popToRoot()
        #expect(coordinator.path.count == 0)
    }

    @Test("PopToRoot on empty path does nothing")
    func popToRootOnEmptyPath() {
        let coordinator = NavigationCoordinator()
        coordinator.popToRoot()
        #expect(coordinator.path.count == 0)
    }
}
