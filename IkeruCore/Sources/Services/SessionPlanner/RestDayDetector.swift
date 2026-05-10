import Foundation

/// Pure decision service. Returns `true` when Home should show the
/// 「今日は休 · Rest day」 state instead of the CTA.
public enum RestDayDetector {

    public static let dueCardCeiling = 5
    public static let skillImbalanceCeiling = 0.15
    public static let inactivityHours = 24.0

    public static func shouldShowRestDay(profile: LearnerSnapshot, now: Date) -> Bool {
        guard profile.dueCardCount < dueCardCeiling else { return false }
        guard profile.skillImbalance <= skillImbalanceCeiling else { return false }
        guard profile.hasNewContentQueued == false else { return false }
        guard let last = profile.lastSessionAt else { return false }
        let hoursSinceLast = now.timeIntervalSince(last) / 3600
        return hoursSinceLast < inactivityHours
    }
}
