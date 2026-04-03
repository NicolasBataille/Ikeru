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
            Color.ikeruBackground
                .ignoresSafeArea()

            if let vm = viewModel, vm.hasLoaded {
                dashboardContent(vm)
            } else {
                Color.ikeruBackground.ignoresSafeArea()
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
            VStack(spacing: IkeruTheme.Spacing.lg) {
                skillRadarSection(vm)
                jlptEstimateCard(vm)
                reviewQueueSection(vm)
                monthlyTrendsSection(vm)
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.top, IkeruTheme.Spacing.md)
            .padding(.bottom, IkeruTheme.Spacing.xxl)
        }
    }

    // MARK: - Skill Radar Section

    @ViewBuilder
    private func skillRadarSection(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            sectionHeader(icon: "chart.pie.fill", title: "Skill Balance")

            SkillRadarView(
                skillBalance: vm.skillBalance,
                variant: .full
            )
            .frame(maxWidth: .infinity)
        }
        .ikeruCard(.standard)
    }

    // MARK: - JLPT Estimate Card

    @ViewBuilder
    private func jlptEstimateCard(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            sectionHeader(icon: "rosette", title: "JLPT Estimate")

            HStack {
                Text(vm.jlptEstimate.level)
                    .font(.ikeruHeading1)
                    .foregroundStyle(Color.ikeruPrimaryAccent)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(vm.jlptDisplayText)
                        .font(.ikeruBody)
                        .foregroundStyle(.white)

                    Text("\(vm.jlptEstimate.masteredCount)/\(vm.jlptEstimate.totalRequired) items")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                }
            }

            // Progress bar
            jlptProgressBar(fraction: vm.jlptEstimate.masteryFraction)
        }
        .ikeruCard(.standard)
    }

    @ViewBuilder
    private func jlptProgressBar(fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                    .fill(Color.white.opacity(0.1))

                RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.ikeruPrimaryAccent,
                                Color.ikeruSuccess
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * min(1.0, max(0, fraction)))
                    .animation(
                        .spring(duration: IkeruTheme.Animation.standardDuration),
                        value: fraction
                    )
            }
        }
        .frame(height: 8)
    }

    // MARK: - Review Queue Section

    @ViewBuilder
    private func reviewQueueSection(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            sectionHeader(icon: "tray.full.fill", title: "Review Queue")

            HStack(spacing: IkeruTheme.Spacing.md) {
                reviewStatBadge(
                    value: "\(vm.dueNowCount)",
                    label: "Due Now",
                    color: vm.dueNowCount > 0
                        ? Color.ikeruSecondaryAccent
                        : Color.ikeruSuccess
                )

                reviewStatBadge(
                    value: "\(vm.dueTodayCount)",
                    label: "Due Today",
                    color: Color.ikeruPrimaryAccent
                )
            }

            // 7-day forecast bar chart
            if !vm.forecast.isEmpty {
                forecastChart(vm)
            }
        }
        .ikeruCard(.standard)
    }

    @ViewBuilder
    private func reviewStatBadge(
        value: String,
        label: String,
        color: Color
    ) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.ikeruHeading2)
                .foregroundStyle(color)

            Text(label)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, IkeruTheme.Spacing.sm)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
    }

    @ViewBuilder
    private func forecastChart(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            Text("7-Day Forecast")
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            HStack(alignment: .bottom, spacing: IkeruTheme.Spacing.xs) {
                ForEach(vm.forecast) { entry in
                    VStack(spacing: 4) {
                        Text("\(entry.cardsDue)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.ikeruTextSecondary)

                        let barHeight = barHeight(
                            value: entry.cardsDue,
                            maxValue: vm.forecastMaxValue
                        )

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.ikeruPrimaryAccent.opacity(0.6),
                                        Color.ikeruPrimaryAccent
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: barHeight)
                            .animation(
                                .spring(duration: IkeruTheme.Animation.standardDuration),
                                value: entry.cardsDue
                            )

                        Text(entry.dayLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(.ikeruTextSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
        }
    }

    // MARK: - Monthly Trends Section

    @ViewBuilder
    private func monthlyTrendsSection(_ vm: ProgressDashboardViewModel) -> some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            sectionHeader(icon: "chart.bar.fill", title: "Monthly Progress")

            if !vm.monthlySnapshots.isEmpty {
                monthlyChart(vm)
            } else {
                Text("Start reviewing to see trends")
                    .font(.ikeruCaption)
                    .foregroundStyle(.ikeruTextSecondary)
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
                        .foregroundStyle(.ikeruTextSecondary)

                    let barHeight = barHeight(
                        value: snapshot.cardsMastered,
                        maxValue: vm.monthlyMaxValue
                    )

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.ikeruSuccess.opacity(0.4),
                                    Color.ikeruSuccess
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: barHeight)
                        .animation(
                            .spring(duration: IkeruTheme.Animation.standardDuration),
                            value: snapshot.cardsMastered
                        )

                    Text(snapshot.monthLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.ikeruTextSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 100)
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.ikeruPrimaryAccent)

            Text(title)
                .font(.ikeruHeading3)
                .foregroundStyle(.white)

            Spacer()
        }
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
