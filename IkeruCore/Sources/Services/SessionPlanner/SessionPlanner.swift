import Foundation

/// Composes `SessionPlan`s for both Home (auto) and Étude (custom) entry
/// points. Pure async function — no side effects, no database writes.
public protocol SessionPlanner: Sendable {
    func compose(inputs: SessionPlannerInputs) async -> SessionPlan
}
