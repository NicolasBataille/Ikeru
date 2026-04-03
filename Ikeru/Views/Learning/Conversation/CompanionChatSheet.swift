import SwiftUI
import IkeruCore

// MARK: - CompanionChatSheet

/// Sheet presentation for the companion chat.
/// Displays companion avatar in the header, message history, and input bar.
struct CompanionChatSheet: View {

    @Bindable var viewModel: CompanionChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            dragIndicator
            headerBar
            Divider().foregroundStyle(Color(hex: IkeruTheme.Colors.surface))
            messageList
            inputBar
        }
        .background(Color(hex: IkeruTheme.Colors.background))
        .confirmationDialog(
            "Clear Chat History",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Messages", role: .destructive) {
                viewModel.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all messages in this conversation.")
        }
        .onAppear {
            viewModel.loadHistory()
        }
    }

    // MARK: - Drag Indicator

    @ViewBuilder
    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 4)
            .padding(.top, IkeruTheme.Spacing.sm)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            // Companion avatar (small, no animation in header)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: IkeruTheme.Colors.primaryAccent),
                                Color(hex: IkeruTheme.Colors.primaryAccent, opacity: 0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Text("\u{3055}") // さ
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.background))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Study Companion")
                    .font(.ikeruHeading3)
                    .foregroundStyle(.white)

                if viewModel.isTyping {
                    Text("typing...")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
                } else {
                    Text("Ask me anything about Japanese!")
                        .font(.ikeruCaption)
                        .foregroundStyle(.ikeruTextSecondary)
                }
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.ikeruTextSecondary)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.ikeruTextSecondary)
            }
        }
        .padding(.horizontal, IkeruTheme.Spacing.md)
        .padding(.vertical, IkeruTheme.Spacing.sm)
    }

    // MARK: - Message List

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: IkeruTheme.Spacing.sm) {
                    ForEach(viewModel.messages, id: \.id) { message in
                        ChatBubbleView(
                            content: message.content,
                            variant: message.role == .user ? .user : .companion
                        )
                        .id(message.id)
                    }

                    if viewModel.isTyping {
                        typingIndicator
                    }
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.vertical, IkeruTheme.Spacing.sm)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isTyping) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    // MARK: - Typing Indicator

    @ViewBuilder
    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color(hex: IkeruTheme.Colors.primaryAccent, opacity: 0.6))
                        .frame(width: 6, height: 6)
                        .offset(y: typingDotOffset(for: index))
                }
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.vertical, IkeruTheme.Spacing.sm + 4)
            .background {
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg)
                    .fill(Color(hex: IkeruTheme.Colors.primaryAccent, opacity: 0.15))
            }

            Spacer()
        }
        .id("typing-indicator")
    }

    @State private var typingAnimationPhase: CGFloat = 0

    private func typingDotOffset(for index: Int) -> CGFloat {
        // Simple static dots — animation kept minimal for performance
        let offset = sin(Double(index) * .pi / 3) * 3
        return CGFloat(offset)
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var inputBar: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            TextField("Ask your companion...", text: $viewModel.inputText, axis: .vertical)
                .font(.ikeruBody)
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.vertical, IkeruTheme.Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: IkeruTheme.Radius.xl)
                        .fill(.ultraThinMaterial)
                }
                .onSubmit {
                    viewModel.sendMessage()
                }

            Button {
                viewModel.sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.ikeruTextSecondary
                            : Color(hex: IkeruTheme.Colors.primaryAccent)
                    )
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, IkeruTheme.Spacing.md)
        .padding(.vertical, IkeruTheme.Spacing.sm)
        .background(Color(hex: IkeruTheme.Colors.surface))
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastId = viewModel.messages.last?.id {
            withAnimation(.easeOut(duration: IkeruTheme.Animation.quickDuration)) {
                proxy.scrollTo(viewModel.isTyping ? "typing-indicator" : lastId, anchor: .bottom)
            }
        }
    }
}

// MARK: - Preview

#Preview("CompanionChatSheet") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            Text("Sheet placeholder")
        }
        .preferredColorScheme(.dark)
}
