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
    case practiceTab
    case exploreTab
    case settingsTab
    case sessionCTA

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
    /// The default "overview of the three tabs" tour. Computed (not a stored
    /// static) so it never becomes shared mutable global state under Swift 6.
    /// Mirrors the beginner-first 3-tab IA: 練習 Practice · 学習 Explore · 設定.
    static var defaultTour: [TourStep] {
        [
        TourStep(
            id: 0,
            target: nil,
            tab: .practice,
            kanji: "\u{59CB}", // 始 — begin
            title: "Tour.Welcome.Title",
            message: "Tour.Welcome.Body"
        ),
        TourStep(
            id: 1,
            target: .practiceTab,
            tab: .practice,
            kanji: "\u{5BB6}", // 家 — home
            title: "Tour.Practice.Title",
            message: "Tour.Practice.Body"
        ),
        TourStep(
            id: 2,
            target: .sessionCTA,
            tab: .practice,
            kanji: "\u{7A3D}\u{53E4}", // 稽古 — practice
            title: "Tour.Session.Title",
            message: "Tour.Session.Body"
        ),
        TourStep(
            id: 3,
            target: .exploreTab,
            tab: .explore,
            kanji: "\u{5B66}", // 学 — study
            title: "Tour.Explore.Title",
            message: "Tour.Explore.Body"
        ),
        TourStep(
            id: 4,
            target: .settingsTab,
            tab: .settings,
            kanji: "\u{8A2D}", // 設 — settings
            title: "Tour.Settings.Title",
            message: "Tour.Settings.Body"
        ),
        TourStep(
            id: 5,
            target: nil,
            tab: .practice,
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
