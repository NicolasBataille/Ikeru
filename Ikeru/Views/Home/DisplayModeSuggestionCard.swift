import SwiftUI
import IkeruCore
import Observation

@Observable
final class DisplayModeSuggestionCardController {

    private static let keyPrefix = "ikeru.display.mode.suggestionShown."

    private let defaults: UserDefaults
    private let profileID: UUID
    private(set) var currentMode: DisplayMode
    private(set) var isEligible: Bool = false

    init(
        defaults: UserDefaults = .standard,
        profileID: UUID,
        currentMode: DisplayMode
    ) {
        self.defaults = defaults
        self.profileID = profileID
        self.currentMode = currentMode
    }

    var shouldShow: Bool {
        guard currentMode == .beginner else { return false }
        guard !alreadyDismissed else { return false }
        return isEligible
    }

    private var alreadyDismissed: Bool {
        defaults.bool(forKey: Self.keyPrefix + profileID.uuidString)
    }

    func onSignalsChanged(reviews: Int, mastery: Int) {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            totalReviewsCompleted: reviews,
            cardsAtFamiliarOrAbove: mastery
        )
        self.isEligible = (result == .eligible)
    }

    func setMode(_ mode: DisplayMode) {
        self.currentMode = mode
    }

    func dismiss() {
        defaults.set(true, forKey: Self.keyPrefix + profileID.uuidString)
        // Trigger Observation update
        self.isEligible = self.isEligible
    }
}

struct DisplayModeSuggestionCard: View {

    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 14) {
                Text("\u{9053}") // 道
                    .font(.system(size: 34, weight: .light, design: .serif))
                    .foregroundStyle(Color.ikeruPrimaryAccent)

                VStack(alignment: .leading, spacing: 6) {
                    Text("DisplayMode.Suggestion.Title")
                        .ikeruScaledFont(15, weight: .semibold, relativeTo: .body)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("DisplayMode.Suggestion.Body")
                        .ikeruScaledFont(13, relativeTo: .body)
                        .foregroundStyle(Color.ikeruTextSecondary)
                    HStack(spacing: 10) {
                        Button(action: onAccept) {
                            Text("DisplayMode.Suggestion.Accept")
                                .ikeruScaledFont(12, weight: .semibold, relativeTo: .caption2)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.ikeruPrimaryAccent)
                                .foregroundStyle(Color.black)
                                .sumiCorners(color: Color.black.opacity(0.3), size: 5, weight: 1.0)
                        }
                        Button(action: onDismiss) {
                            Text("DisplayMode.Suggestion.Later")
                                .ikeruScaledFont(12, relativeTo: .caption2)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(TatamiTokens.paperGhost, lineWidth: 1)
                                )
                                .foregroundStyle(Color.ikeruTextSecondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .tatamiRoom(.standard, padding: 18)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TatamiTokens.paperGhost)
                    .padding(12)
            }
            .accessibilityLabel("Dismiss")
        }
    }
}
