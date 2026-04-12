import SwiftUI
import SwiftData
import IkeruCore

// MARK: - ProgressDashboardView

/// Full progress dashboard showing skill radar, JLPT estimate, review queue, and trends.
struct ProgressDashboardView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ProgressDashboardViewModel?

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            if let vm = viewModel, vm.hasLoaded {
                dashboardContent(vm)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            initializeViewModel()
            await viewModel?.loadData()
        }
        .onAppear {
            if viewModel != nil {
                Task { await viewModel?.loadData() }
            }
        }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private func dashboardContent(_ vm: ProgressDashboardViewModel) -> some View {
        ScrollView {
            VStack(spacing: IkeruTheme.Spacing.xl) {
                topBar
                kanaEntryLink
                dictionaryEntryLink
                jlptEstimateCard(vm)
                skillRadarSection(vm)
                reviewQueueSection(vm)
                monthlyTrendsSection(vm)

                Spacer(minLength: 200)
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.top, IkeruTheme.Spacing.lg)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR PATH")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("Progress")
                .font(.ikeruDisplaySmall)
                .ikeruTracking(.display)
                .foregroundStyle(Color.ikeruTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Kana entry link

    private var kanaEntryLink: some View {
        NavigationLink {
            KanaPoolSelectorView()
        } label: {
            HStack(spacing: IkeruTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.ikeruPrimaryAccent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Text("あ")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kana")
                        .font(.ikeruHeading3)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("Hiragana & katakana, par groupes")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
            .ikeruCard(.interactive)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dictionary entry link

    private var dictionaryEntryLink: some View {
        NavigationLink {
            VocabularyDictionaryView()
        } label: {
            HStack(spacing: IkeruTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.ikeruSecondaryAccent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Text("辞")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ikeruSecondaryAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictionary")
                        .font(.ikeruHeading3)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("Personal vocabulary collection")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
            .ikeruCard(.interactive)
        }
        .buttonStyle(.plain)
    }

    // MARK: - JLPT Estimate

    @ViewBuilder
    private func jlptEstimateCard(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "JLPT Estimate", eyebrow: "Mastery")

            HStack(alignment: .lastTextBaseline) {
                Text(vm.jlptEstimate.level)
                    .font(.ikeruDisplayLarge)
                    .ikeruTracking(.display)
                    .foregroundStyle(LinearGradient.ikeruGold)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(vm.jlptDisplayText)
                        .font(.ikeruBody)
                        .foregroundStyle(Color.ikeruTextPrimary)

                    Text("\(vm.jlptEstimate.masteredCount)/\(vm.jlptEstimate.totalRequired) items")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
            }

            jlptProgressBar(fraction: vm.jlptEstimate.masteryFraction)
        }
        .ikeruCard(.hero)
    }

    @ViewBuilder
    private func jlptProgressBar(fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(LinearGradient.ikeruGold)
                    .frame(width: geometry.size.width * min(1.0, max(0, fraction)))
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.86),
                        value: fraction
                    )
            }
        }
        .frame(height: 8)
    }

    // MARK: - Skill Radar

    @ViewBuilder
    private func skillRadarSection(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Skill Balance", eyebrow: "Strengths")

            SkillRadarView(
                skillBalance: vm.skillBalance,
                variant: .full
            )
            .frame(maxWidth: .infinity)
        }
        .ikeruCard(.standard)
    }

    // MARK: - Review Queue

    @ViewBuilder
    private func reviewQueueSection(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Review Queue", eyebrow: "Today")

            HStack(spacing: IkeruTheme.Spacing.md) {
                reviewStatTile(
                    value: "\(vm.dueNowCount)",
                    label: "Due Now",
                    tint: vm.dueNowCount > 0
                        ? Color.ikeruSecondaryAccent
                        : Color.ikeruTertiaryAccent
                )

                reviewStatTile(
                    value: "\(vm.dueTodayCount)",
                    label: "Due Today",
                    tint: Color.ikeruPrimaryAccent
                )
            }

            if !vm.forecast.isEmpty {
                forecastChart(vm)
                    .padding(.top, IkeruTheme.Spacing.sm)
            }
        }
        .ikeruCard(.standard)
    }

    @ViewBuilder
    private func reviewStatTile(
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(spacing: IkeruTheme.Spacing.xs) {
            Text(value)
                .font(.ikeruStatsLarge)
                .foregroundStyle(tint)

            Text(label.uppercased())
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.md)
        .ikeruGlass(
            cornerRadius: IkeruTheme.Radius.md,
            tint: tint,
            tintOpacity: 0.08
        )
    }

    @ViewBuilder
    private func forecastChart(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Text("7-DAY FORECAST")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)

            HStack(alignment: .bottom, spacing: IkeruTheme.Spacing.xs) {
                ForEach(vm.forecast) { entry in
                    VStack(spacing: 4) {
                        Text("\(entry.cardsDue)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.ikeruTextSecondary)

                        let h = barHeight(value: entry.cardsDue, maxValue: vm.forecastMaxValue)

                        Capsule()
                            .fill(LinearGradient.ikeruGold)
                            .frame(height: h)
                            .animation(
                                .spring(response: 0.42, dampingFraction: 0.86),
                                value: entry.cardsDue
                            )

                        Text(entry.dayLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.ikeruTextTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
        }
    }

    // MARK: - Monthly Trends

    @ViewBuilder
    private func monthlyTrendsSection(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.md) {
            IkeruSectionHeader(title: "Monthly Progress", eyebrow: "Trends")

            if !vm.monthlySnapshots.isEmpty {
                monthlyChart(vm)
            } else {
                Text("Start reviewing to see trends.")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, IkeruTheme.Spacing.md)
            }
        }
        .ikeruCard(.standard)
    }

    @ViewBuilder
    private func monthlyChart(_ vm: ProgressDashboardViewModel) -> some View {
        HStack(alignment: .bottom, spacing: IkeruTheme.Spacing.sm) {
            ForEach(vm.monthlySnapshots) { snapshot in
                VStack(spacing: 4) {
                    Text("\(snapshot.cardsMastered)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.ikeruTextSecondary)

                    let h = barHeight(value: snapshot.cardsMastered, maxValue: vm.monthlyMaxValue)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.ikeruTertiaryAccent.opacity(0.4),
                                    Color.ikeruTertiaryAccent
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: h)
                        .animation(
                            .spring(response: 0.42, dampingFraction: 0.86),
                            value: snapshot.cardsMastered
                        )

                    Text(snapshot.monthLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 100)
    }

    // MARK: - Helpers

    private func barHeight(value: Int, maxValue: Int) -> CGFloat {
        let maxBarHeight: CGFloat = 60
        let minBarHeight: CGFloat = 4
        guard maxValue > 0 else { return minBarHeight }
        let fraction = Double(value) / Double(maxValue)
        return max(minBarHeight, maxBarHeight * fraction)
    }

    private func initializeViewModel() {
        guard viewModel == nil else { return }
        let container = modelContext.container
        viewModel = ProgressDashboardViewModel(modelContainer: container)
    }
}

// MARK: - Preview

#Preview("Progress Dashboard") {
    NavigationStack {
        ProgressDashboardView()
    }
    .preferredColorScheme(.dark)
}
