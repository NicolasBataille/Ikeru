import SwiftUI

// MARK: - Feature Tour Model
//
// A coach-mark style guided tour that runs *inside* the live app (not the
// sign-up slides). It dims the screen and punches a spotlight around the real
// UI element being explained — tab buttons, the practice CTA, the Sakura
// avatar — with a localized callout bubble. Aimed at newcomers with little or
// no Japanese, so the copy stays plain and reassuring.

/// A UI element the tour can spotlight. Views opt in by tagging themselves with
/// `.tourAnchor(_:)`; the overlay resolves the live frame from the collected
/// anchors at render time.
enum TourTarget: String, CaseIterable, Identifiable, Sendable {
    case homeTab
    case studyTab
    case companionTab
    case rpgTab
    case settingsTab
    case sessionCTA
    case companionAvatar

    var id: String { rawValue }
}

/// One stop on the tour.
struct TourStep: Identifiable {
    let id: Int
    /// Element to spotlight. `nil` renders a centered card with no cutout
    /// (used for the welcome and closing steps).
    let target: TourTarget?
    /// Tab to switch to before showing this step, so the user sees the
    /// destination behind the spotlight. `nil` leaves the current tab as-is.
    let tab: AppTab?
    /// Small decorative kanji shown in the bubble — on-brand flavor, glossed by
    /// the surrounding copy so it never blocks comprehension.
    let kanji: String?
    let title: LocalizedStringKey
    let message: LocalizedStringKey
}

extension TourStep {
    /// The default "overview of the five tabs" tour. Computed (not a stored
    /// static) so it never becomes shared mutable global state under Swift 6.
    static var defaultTour: [TourStep] {
        [
        TourStep(
            id: 0,
            target: nil,
            tab: .home,
            kanji: "\u{59CB}", // 始 — begin
            title: "Tour.Welcome.Title",
            message: "Tour.Welcome.Body"
        ),
        TourStep(
            id: 1,
            target: .homeTab,
            tab: .home,
            kanji: "\u{5BB6}", // 家 — home
            title: "Tour.Home.Title",
            message: "Tour.Home.Body"
        ),
        TourStep(
            id: 2,
            target: .sessionCTA,
            tab: .home,
            kanji: "\u{7A3D}\u{53E4}", // 稽古 — practice
            title: "Tour.Session.Title",
            message: "Tour.Session.Body"
        ),
        TourStep(
            id: 3,
            target: .studyTab,
            tab: .study,
            kanji: "\u{5B66}", // 学 — study
            title: "Tour.Study.Title",
            message: "Tour.Study.Body"
        ),
        TourStep(
            id: 4,
            target: .companionAvatar,
            tab: nil, // keep a non-companion tab so the floating avatar stays visible
            kanji: "\u{53CB}", // 友 — friend
            title: "Tour.Companion.Title",
            message: "Tour.Companion.Body"
        ),
        TourStep(
            id: 5,
            target: .rpgTab,
            tab: .rpg,
            kanji: "\u{6BB5}", // 段 — rank
            title: "Tour.RPG.Title",
            message: "Tour.RPG.Body"
        ),
        TourStep(
            id: 6,
            target: .settingsTab,
            tab: .settings,
            kanji: "\u{8A2D}", // 設 — settings
            title: "Tour.Settings.Title",
            message: "Tour.Settings.Body"
        ),
        TourStep(
            id: 7,
            target: nil,
            tab: .home,
            kanji: "\u{884C}", // 行 — go
            title: "Tour.Finish.Title",
            message: "Tour.Finish.Body"
        ),
        ]
    }
}

// MARK: - Anchor plumbing

/// Collects the live frame of every tour target in a shared coordinate space.
struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TourTarget: Anchor<CGRect>],
        nextValue: () -> [TourTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as a spotlight target for the feature tour.
    func tourAnchor(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
    }
}
