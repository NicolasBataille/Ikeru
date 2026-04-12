import SwiftUI
import IkeruCore
import os

// MARK: - RigJobsView
//
// Story 7.5 Task 1: lists in-flight rig jobs the app is tracking, with
// pull-to-refresh, auto-poll every 2 s while visible, and a detail sheet
// allowing retry/cancel.

struct RigJobsView: View {

    @State private var viewModel: RigJobsViewModel
    @State private var selectedJob: RigJobRecord?

    init(client: RigClient) {
        _viewModel = State(initialValue: RigJobsViewModel(client: client))
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()
            content(viewModel: viewModel)
        }
        .navigationTitle("Rig Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    @ViewBuilder
    private func content(viewModel: RigJobsViewModel) -> some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruDanger)
                }
                .listRowBackground(Color.clear)
            }

            if viewModel.jobs.isEmpty {
                Section {
                    Text("No jobs tracked yet. Generate audio or images to populate this list.")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(viewModel.jobs, id: \.id) { job in
                        Button {
                            selectedJob = job
                        } label: {
                            RigJobRow(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: Binding(
            get: { selectedJob != nil },
            set: { if !$0 { selectedJob = nil } }
        )) {
            if let job = selectedJob {
                RigJobDetailSheet(
                job: job,
                onRetry: {
                    Task {
                        await viewModel.retry(job)
                        selectedJob = nil
                    }
                },
                onCancel: {
                    Task {
                        await viewModel.cancel(job)
                        selectedJob = nil
                    }
                }
            )
            }
        }
    }
}

// MARK: - Row

private struct RigJobRow: View {

    let job: RigJobRecord

    var body: some View {
        HStack(spacing: IkeruTheme.Spacing.md) {
            Image(systemName: iconName(for: job.type))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(paramsSummary(job.params))
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    statusBadge

                    Text(elapsedString(from: job.createdAt))
                        .font(.ikeruMicro)
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ikeruTextTertiary)
        }
        .padding(.vertical, IkeruTheme.Spacing.xs)
        .contentShape(Rectangle())
    }

    private var statusBadge: some View {
        Text(job.status.uppercased())
            .font(.ikeruMicro)
            .ikeruTracking(.micro)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(statusColor(for: job.status))
            }
    }
}

// MARK: - Detail sheet

private struct RigJobDetailSheet: View {

    let job: RigJobRecord
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                IkeruScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                        header

                        if let error = job.error {
                            errorBlock(error)
                        }

                        paramsBlock

                        actionsBlock
                    }
                    .padding(IkeruTheme.Spacing.md)
                }
            }
            .navigationTitle("Job")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.type.uppercased())
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text(job.id)
                .font(.ikeruBody)
                .foregroundStyle(Color.ikeruTextPrimary)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Text(job.status.uppercased())
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background { Capsule().fill(statusColor(for: job.status)) }

                Text(elapsedString(from: job.createdAt))
                    .font(.ikeruMicro)
                    .foregroundStyle(Color.ikeruTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Text("ERROR")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text(message)
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruDanger)
        }
        .ikeruCard(.standard)
    }

    private var paramsBlock: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.sm) {
            Text("PARAMS")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            ForEach(job.params.keys.sorted(), id: \.self) { key in
                HStack(alignment: .top) {
                    Text(key)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                    Spacer()
                    Text(stringValue(job.params[key]))
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextPrimary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .ikeruCard(.standard)
    }

    private var actionsBlock: some View {
        HStack(spacing: IkeruTheme.Spacing.md) {
            if job.isError {
                Button("Retry", action: onRetry)
                    .ikeruButtonStyle(.glassPill)
            }
            if !job.isTerminal {
                Button("Cancel", role: .destructive, action: onCancel)
                    .ikeruButtonStyle(.glassPill)
            }
        }
    }

    private func stringValue(_ value: RigJSONValue?) -> String {
        guard let value else { return "—" }
        switch value {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return "null"
        }
    }
}

// MARK: - Shared formatters

private func iconName(for type: String) -> String {
    switch type {
    case "tts": return "waveform"
    case "image": return "photo"
    default: return "gearshape"
    }
}

private func statusColor(for status: String) -> Color {
    switch status {
    case "queued": return Color.gray
    case "running": return Color.blue
    case "done": return Color.green
    case "error": return Color.red
    default: return Color.gray
    }
}

private func paramsSummary(_ params: [String: RigJSONValue]) -> String {
    if case .string(let text) = params["text"] {
        return truncate(text, to: 60)
    }
    let joined = params.keys.sorted().prefix(3).map { key -> String in
        let value: String
        switch params[key] {
        case .string(let s): value = s
        case .int(let i): value = String(i)
        case .double(let d): value = String(d)
        case .bool(let b): value = String(b)
        case .null, .none: value = "—"
        }
        return "\(key)=\(value)"
    }.joined(separator: " ")
    return truncate(joined, to: 60)
}

private func truncate(_ text: String, to limit: Int) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(limit - 1)) + "…"
}

private func elapsedString(from date: Date) -> String {
    let elapsed = Int(Date.now.timeIntervalSince(date))
    let minutes = max(0, elapsed) / 60
    let seconds = max(0, elapsed) % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

