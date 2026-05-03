import SwiftUI
import IkeruCore

struct CustomPlannerSheet: View {

    let unlockedTypes: Set<ExerciseType>
    let onCompose: (Set<ExerciseType>, Set<JLPTLevel>, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("ikeru.session.defaultDurationMinutes") private var initialDuration = 15
    @AppStorage("ikeru.etude.lastTypes") private var lastTypesData: Data = .init()
    @AppStorage("ikeru.etude.lastLevels") private var lastLevelsData: Data = .init()

    @State private var selectedTypes: Set<ExerciseType> = []
    @State private var selectedLevels: Set<JLPTLevel> = [.n5]
    @State private var duration: Int = 15

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sectionTypes
                    sectionLevels
                    sectionDuration
                    composeButton
                }
                .padding(20)
            }
            .background(Color.ikeruBackground.ignoresSafeArea())
            .navigationTitle(Text("Etude.Compose.Title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Etude.Compose.Cancel") { dismiss() }
                }
            }
            .onAppear {
                duration = initialDuration
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
    }

    private var sectionTypes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Etude.Compose.Types")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ikeruTextSecondary)
            FlowChips(items: ExerciseType.allCases.filter { unlockedTypes.contains($0) }) { type in
                ChipButton(
                    label: ExerciseTileTokens.label(for: type),
                    isSelected: selectedTypes.contains(type)
                ) {
                    if selectedTypes.contains(type) { selectedTypes.remove(type) }
                    else { selectedTypes.insert(type) }
                }
            }
        }
    }

    private var sectionLevels: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Etude.Compose.Levels")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ikeruTextSecondary)
            FlowChips(items: JLPTLevel.allCases) { level in
                ChipButton(
                    label: LocalizedStringKey(level.displayLabel),
                    isSelected: selectedLevels.contains(level)
                ) {
                    if selectedLevels.contains(level) { selectedLevels.remove(level) }
                    else { selectedLevels.insert(level) }
                }
            }
        }
    }

    private var sectionDuration: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Etude.Compose.Duration")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ikeruTextSecondary)
            Picker("", selection: $duration) {
                ForEach([5, 15, 30, 45], id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
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
                Text("Etude.Compose.Action")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.6)
                Spacer()
            }
            .foregroundStyle(Color.ikeruBackground)
            .padding(.vertical, 14)
            .background(canCompose
                        ? Color.ikeruPrimaryAccent
                        : Color.ikeruPrimaryAccent.opacity(0.35))
        }
        .buttonStyle(.plain)
        .disabled(!canCompose)
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
    let label: LocalizedStringKey
    let isSelected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.ikeruBackground : Color.ikeruTextPrimary)
                .background(isSelected ? Color.ikeruPrimaryAccent : Color.white.opacity(0.04))
                .overlay(Rectangle().strokeBorder(TatamiTokens.goldDim, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
