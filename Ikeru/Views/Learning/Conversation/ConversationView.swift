import SwiftUI
import IkeruCore
import os

// MARK: - Conversation View

/// Chat interface for the AI conversation partner.
/// Displays a scrollable message list with text/voice input.
struct ConversationView: View {

    @State private var viewModel: ConversationViewModel

    init(viewModel: ConversationViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if !viewModel.isAIAvailable {
                    aiUnavailableSection
                } else if viewModel.showWelcome {
                    welcomeSection
                } else {
                    messageList
                }

                if viewModel.isAIAvailable {
                    inputBar
                        .padding(.bottom, 88) // Floating tab bar clearance
                }
            }
        }
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                levelBadge
            }
        }
        .task {
            await viewModel.onAppear()
        }
    }

    // MARK: - AI Unavailable Section

    private var aiUnavailableSection: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(Color.gray.opacity(0.5))

            VStack(spacing: IkeruTheme.Spacing.sm) {
                Text("AI not configured")
                    .font(.ikeruHeading1)
                    .foregroundStyle(.white)

                Text("To chat with Sakura, set up an AI provider in Settings.")
                    .font(.ikeruBody)
                    .foregroundStyle(.ikeruTextSecondary)
                    .multilineTextAlignment(.center)
            }

            NavigationLink {
                AISettingsView()
            } label: {
                HStack(spacing: 10) {
                    Text("Set Up AI")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .ikeruButtonStyle(.primary)
            .padding(.horizontal, IkeruTheme.Spacing.xl)

            Spacer()
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
    }

    // MARK: - Welcome Section

    private var welcomeSection: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: IkeruTheme.Colors.primaryAccent),
                            Color(hex: IkeruTheme.Colors.success)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: IkeruTheme.Spacing.sm) {
                Text("Meet Sakura")
                    .font(.ikeruHeading1)
                    .foregroundStyle(.white)

                Text("Your Japanese conversation partner")
                    .font(.ikeruBody)
                    .foregroundStyle(.ikeruTextSecondary)

                Text("Level: \(viewModel.jlptLevel.rawValue)")
                    .font(.ikeruCaption)
                    .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
                    .padding(.top, IkeruTheme.Spacing.xs)
            }

            VStack(spacing: IkeruTheme.Spacing.sm) {
                suggestionButton("こんにちは！")
                suggestionButton("今日は何をしましたか？")
                suggestionButton("Hello! I'm learning Japanese.")
            }
            .padding(.top, IkeruTheme.Spacing.md)

            Spacer()
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
    }

    // MARK: - Suggestion Button

    private func suggestionButton(_ text: String) -> some View {
        Button {
            Task { await viewModel.sendMessage(text) }
        } label: {
            Text(text)
                .font(.ikeruBody)
                .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.vertical, IkeruTheme.Spacing.sm)
                .background(
                    Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.1)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.3),
                            lineWidth: 1
                        )
                )
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: IkeruTheme.Spacing.md) {
                    ForEach(viewModel.messages) { message in
                        ConversationBubbleView(message: message)
                            .id(message.id)
                    }

                    if viewModel.isLoading {
                        typingIndicator
                            .id("typing-indicator")
                    }

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.top, IkeruTheme.Spacing.md)
                .padding(.bottom, IkeruTheme.Spacing.lg)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    scrollToTypingIndicator(proxy: proxy)
                }
            }
        }
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: IkeruTheme.Spacing.xs) {
                ForEach(0..<3, id: \.self) { index in
                    TypingDot(delay: Double(index) * 0.2)
                }
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.vertical, IkeruTheme.Spacing.sm)
            .background(Color(hex: IkeruTheme.Colors.surface))
            .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg))

            Spacer()
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: IkeruTheme.Colors.secondaryAccent))

            Text(message)
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            Spacer()

            Button("Retry") {
                Task { await viewModel.sendMessage() }
            }
            .font(.ikeruCaption)
            .fontWeight(.semibold)
            .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
        }
        .padding(IkeruTheme.Spacing.sm)
        .background(Color(hex: IkeruTheme.Colors.secondaryAccent).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.sm))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.1))

            HStack(spacing: IkeruTheme.Spacing.sm) {
                voiceButton

                TextField("Type in Japanese...", text: $viewModel.inputText, axis: .vertical)
                    .font(.ikeruBody)
                    .foregroundStyle(.white)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, IkeruTheme.Spacing.sm)
                    .padding(.vertical, IkeruTheme.Spacing.sm)
                    .background(Color(hex: IkeruTheme.Colors.surface))
                    .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg))
                    .onSubmit {
                        Task { await viewModel.sendMessage() }
                    }

                sendButton
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.vertical, IkeruTheme.Spacing.sm)
            .background(Color.ikeruBackground)
        }
    }

    // MARK: - Voice Button

    private var voiceButton: some View {
        Button {
            viewModel.toggleVoiceInput()
        } label: {
            Image(systemName: viewModel.isVoiceActive ? "mic.fill" : "mic")
                .font(.system(size: 20))
                .foregroundStyle(
                    viewModel.isVoiceActive
                        ? Color(hex: IkeruTheme.Colors.secondaryAccent)
                        : .ikeruTextSecondary
                )
                .frame(width: 36, height: 36)
                .background(
                    viewModel.isVoiceActive
                        ? Color(hex: IkeruTheme.Colors.secondaryAccent).opacity(0.15)
                        : Color.clear
                )
                .clipShape(Circle())
                .animation(.easeInOut(duration: 0.2), value: viewModel.isVoiceActive)
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            Task { await viewModel.sendMessage() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(
                    viewModel.canSend
                        ? Color(hex: IkeruTheme.Colors.primaryAccent)
                        : .ikeruTextSecondary
                )
                .animation(.easeInOut(duration: 0.15), value: viewModel.canSend)
        }
        .disabled(!viewModel.canSend)
    }

    // MARK: - Level Badge

    private var levelBadge: some View {
        Text(viewModel.jlptLevel.rawValue)
            .font(.ikeruCaption)
            .fontWeight(.semibold)
            .foregroundStyle(Color(hex: IkeruTheme.Colors.primaryAccent))
            .padding(.horizontal, IkeruTheme.Spacing.sm)
            .padding(.vertical, IkeruTheme.Spacing.xs)
            .background(
                Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.15)
            )
            .clipShape(Capsule())
    }

    // MARK: - Scroll Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessage = viewModel.messages.last else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    private func scrollToTypingIndicator(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo("typing-indicator", anchor: .bottom)
        }
    }
}

// MARK: - Typing Dot

private struct TypingDot: View {

    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.6))
            .frame(width: 8, height: 8)
            .offset(y: isAnimating ? -4 : 0)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatForever()
                .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Preview

#Preview("Conversation View") {
    NavigationStack {
        ConversationView(
            viewModel: ConversationViewModel(
                conversationService: ConversationService(
                    aiRouter: AIRouterService()
                ),
                jlptLevel: .n5
            )
        )
    }
    .preferredColorScheme(.dark)
}
