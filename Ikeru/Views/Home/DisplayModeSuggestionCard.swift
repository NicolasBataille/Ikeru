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

    func onSignalsChanged(streak: Int, reviews: Int, mastery: Int) {
        let result = DisplayModeAdvancedThresholdMonitor.evaluate(
            currentDailyStreak: streak,
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("DisplayMode.Suggestion.Body")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ikeruTextSecondary)
                    HStack(spacing: 10) {
                        Button(action: onAccept) {
                            Text("DisplayMode.Suggestion.Accept")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.ikeruPrimaryAccent)
                                .foregroundStyle(Color.black)
                                .cornerRadius(6)
                        }
                        Button(action: onDismiss) {
                            Text("DisplayMode.Suggestion.Later")
                                .font(.system(size: 12))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(TatamiTokens.paperGhost, lineWidth: 1)
                                )
                                .foregroundStyle(Color.ikeruTextSecondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [
                        Color.ikeruPrimaryAccent.opacity(0.06),
                        Color.ikeruPrimaryAccent.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.ikeruPrimaryAccent.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

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
