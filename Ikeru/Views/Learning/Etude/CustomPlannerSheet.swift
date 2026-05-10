import SwiftUI
import IkeruCore

struct CustomPlannerSheet: View {

    let unlockedTypes: Set<ExerciseType>
    let onCompose: (Set<ExerciseType>, Set<JLPTLevel>, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    // Picker binds directly to AppStorage so the Compose sheet is the
    // single source of truth for the default session length. Settings
    // used to mirror this row; it was removed when the picker moved here.
    @AppStorage("ikeru.session.defaultDurationMinutes") private var duration = 15
    @AppStorage("ikeru.etude.lastTypes") private var lastTypesData: Data = .init()
    @AppStorage("ikeru.etude.lastLevels") private var lastLevelsData: Data = .init()

    @State private var selectedTypes: Set<ExerciseType> = []
    @State private var selectedLevels: Set<JLPTLevel> = [.n5]

    var body: some View {
        // NavigationStack gives the sheet proper top safe-area handling
        // (the previous ZStack-only layout cropped the title under the
        // status bar). Nav bar is hidden because we render our own
        // tatami-styled header inside the scroll view.
        NavigationStack {
            ZStack {
                IkeruScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                        sectionTypes
                        sectionLevels
                        sectionDuration
                        composeButton
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if let restored = try? JSONDecoder().decode(Set<ExerciseType>.self, from: lastTypesData),
               !restored.isEmpty {
                selectedTypes = restored.intersection(unlockedTypes)
            }
            if let restored = try? JSONDecoder().decode(Set<JLPTLevel>.self, from: lastLevelsData),
               !restored.isEmpty {
                selectedLevels = restored
            }
        }
    }

    // MARK: - Header

    /// Two-row header — top: small dismiss "X" pinned right; bottom:
    /// centered serif title with a kanji eyebrow. Gives the title full
    /// horizontal room (no longer wraps to two lines next to a button).
    private var header: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ikeruTextSecondary)
                        .frame(width: 36, height: 36)
                        .background {
                            Circle().fill(.ultraThinMaterial)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Etude.Compose.Cancel"))
            }

            VStack(spacing: 4) {
                Text("\u{7DE8}\u{6210}")             // 編成
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text("Etude.Compose.Title")
                    .font(.system(size: 30, weight: .light, design: .serif))
                    .italic()
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var sectionTypes: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(japanese: "\u{7A3D}\u{53E4}", chrome: "Etude.Compose.Types")
            FlowChips(items: ExerciseType.allCases.filter { unlockedTypes.contains($0) }) { type in
                ChipButton(
                    label: Text(ExerciseTileTokens.label(for: type)),
                    isSelected: selectedTypes.contains(type)
                ) {
                    if selectedTypes.contains(type) { selectedTypes.remove(type) }
                    else { selectedTypes.insert(type) }
                }
            }
        }
    }

    private var sectionLevels: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(japanese: "\u{7D1A}", chrome: "Etude.Compose.Levels")
            FlowChips(items: JLPTLevel.allCases) { level in
                ChipButton(
                    label: Text(verbatim: level.displayLabel),
                    isSelected: selectedLevels.contains(level)
                ) {
                    if selectedLevels.contains(level) { selectedLevels.remove(level) }
                    else { selectedLevels.insert(level) }
                }
            }
        }
    }

    /// Duration picker now uses the same chip pattern as types/levels
    /// instead of an iOS native segmented control. Visual consistency
    /// with the rest of the wabi-sabi chrome.
    private var sectionDuration: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(japanese: "\u{6642}\u{9593}", chrome: "Etude.Compose.Duration")
            FlowChips(items: [5, 15, 30, 45]) { minutes in
                ChipButton(
                    label: Text(verbatim: "\(minutes) min"),
                    isSelected: duration == minutes
                ) {
                    duration = minutes
                }
            }
        }
    }

    /// Bilingual section header — kanji eyebrow + localized chrome label.
    /// Replaces the prior plain-text labels for visual consistency with
    /// the rest of the app's wabi-sabi chrome.
    private func sectionLabel(japanese: String, chrome: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Text(japanese)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(TatamiTokens.paperGhost)
            Text(chrome)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.ikeruTextSecondary)
        }
    }

    private var composeButton: some View {
        Button {
            lastTypesData = (try? JSONEncoder().encode(selectedTypes)) ?? .init()
            lastLevelsData = (try? JSONEncoder().encode(selectedLevels)) ?? .init()
            onCompose(selectedTypes, selectedLevels, duration)
            dismiss()
        } label: {
            HStack {
                Spacer()
                Text("\u{7DE8}\u{6210}\u{30FB}")
                    .font(.system(size: 13, weight: .regular, design: .serif))
                Text("Etude.Compose.Action")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.6)
                Spacer()
            }
            .foregroundStyle(Color.ikeruBackground)
            .padding(.vertical, 16)
            .background(canCompose
                        ? Color.ikeruPrimaryAccent
                        : Color.ikeruPrimaryAccent.opacity(0.35))
            .sumiCorners(color: Color.ikeruBackground.opacity(0.6),
                         size: 6, weight: 1.2, inset: -1)
        }
        .buttonStyle(.plain)
        .disabled(!canCompose)
        .padding(.top, 10)
    }

    private var canCompose: Bool {
        !selectedTypes.isEmpty && !selectedLevels.isEmpty
    }
}

private struct FlowChips<Item: Hashable, Cell: View>: View {
    let items: [Item]
    let cell: (Item) -> Cell
    init(items: [Item], @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.items = items
        self.cell = cell
    }
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { cell($0) }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if rowWidth + s.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = s.width + spacing
                rowHeight = s.height
            } else {
                rowWidth += s.width + spacing
                rowHeight = max(rowHeight, s.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y),
                      proposal: ProposedViewSize(width: s.width, height: s.height))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

private struct ChipButton: View {
    let label: Text
    let isSelected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            label
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.ikeruBackground : Color.ikeruTextPrimary)
                .background(isSelected ? Color.ikeruPrimaryAccent : Color.white.opacity(0.04))
                .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
