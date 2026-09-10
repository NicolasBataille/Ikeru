import SwiftUI
import IkeruCore
import os

// MARK: - Conversation View

/// Chat interface for the AI conversation partner.
/// Displays a scrollable message list with text/voice input.
struct ConversationView: View {

    @State private var viewModel: ConversationViewModel
    /// True until the async provider-availability sweep finishes, so we show a
    /// spinner instead of flashing the "no AI" section while it's still unknown.
    @State private var isInitializing = true
    /// In-app language (FR/EN), injected at the root via AppLocale. Drives which
    /// language the beginner starter chips open in, and is mirrored onto
    /// `viewModel.interfaceLocale` so Sakura's translations/corrections are
    /// written in this language rather than guessed from the learner's text.
    @Environment(\.locale) private var locale

    init(viewModel: ConversationViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground(variant: .auxiliary)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if isInitializing {
                    loadingSection
                } else if !viewModel.isAIAvailable {
                    aiUnavailableSection
                } else if viewModel.showWelcome {
                    welcomeSection
                } else {
                    messageList
                        // Tap (not drag) anywhere on the message list dismisses
                        // the keyboard so the user can scroll/read without it.
                        .onTapGesture {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil, from: nil, for: nil
                            )
                        }
                }

                if !isInitializing && viewModel.isAIAvailable {
                    inputBar
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
            // Mirror the in-app language into the view model BEFORE onAppear —
            // onAppear can immediately send a seeded opening message, and that
            // first send must already carry the right interfaceLocale.
            viewModel.interfaceLocale = locale
            await viewModel.onAppear()
            isInitializing = false
        }
        .onChange(of: locale) { _, newLocale in
            viewModel.interfaceLocale = newLocale
        }
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Spacer()
            ProgressView()
                .tint(Color.ikeruPrimaryAccent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - AI Unavailable Section

    private var aiUnavailableSection: some View {
        VStack(spacing: IkeruTheme.Spacing.lg) {
            Spacer()

            Text("\u{6843}") // 桜
                .font(.system(size: 64, weight: .light, design: .serif))
                .foregroundStyle(Color.ikeruPrimaryAccent.opacity(0.45))

            // Offline and "no key configured" are different situations: nudging
            // an offline learner to go set up an AI key is a dark pattern (there
            // is nothing they can do about it right now), so the two get
            // distinct, honest copy.
            if viewModel.isOffline {
                offlineNotice
            } else {
                keySetupCTA
            }

            Spacer()
        }
        .padding(.horizontal, IkeruTheme.Spacing.lg)
    }

    /// Shown when the device has no network. No setup button — there is
    /// nothing actionable to offer while offline.
    private var offlineNotice: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text("Sakura.NoAI.Title")
                .ikeruScaledFont(22, weight: .light, design: .serif, relativeTo: .title3)
                .foregroundStyle(Color.ikeruTextPrimary)
                .multilineTextAlignment(.center)

            Text("Sakura.NoAI.Offline")
                .ikeruScaledFont(14, relativeTo: .body)
                .foregroundStyle(Color.ikeruTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, IkeruTheme.Spacing.lg)
        }
    }

    /// Compact "bring your own key" CTA — shown only when the device is
    /// online and simply has no working AI provider configured, so setting
    /// one up in Settings → AI is an action the learner can take right now.
    private var keySetupCTA: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            Text("Sakura.NoAI.KeySetup")
                .ikeruScaledFont(14, relativeTo: .body)
                .foregroundStyle(Color.ikeruTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, IkeruTheme.Spacing.lg)

            NavigationLink {
                AISettingsView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Sakura.NoAI.Setup")
                        .ikeruScaledFont(13, weight: .bold, relativeTo: .caption)
                        .tracking(1.4)
                }
                .foregroundStyle(Color.ikeruBackground)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.ikeruPrimaryAccent)
                .sumiCorners(color: Color.ikeruBackground.opacity(0.6),
                             size: 6, weight: 1.2, inset: -1)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Welcome Section

    private var welcomeSection: some View {
        ScrollView {
            VStack(spacing: IkeruTheme.Spacing.xl) {
                Spacer(minLength: IkeruTheme.Spacing.xl)

                // Canonical Sakura avatar — square sumi frame with 桜 serif
                ZStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.165, green: 0.133, blue: 0.102),
                                    Color(red: 0.078, green: 0.067, blue: 0.051)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Rectangle()
                                .strokeBorder(TatamiTokens.goldDim, lineWidth: 1)
                        )
                        .frame(width: 80, height: 80)
                        .sumiCorners(color: .ikeruPrimaryAccent, size: 10, weight: 1.4, inset: -1)

                    Text("\u{685C}") // 桜
                        .font(.system(size: 44, weight: .light, design: .serif))
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                }

                // Title + descriptor
                VStack(spacing: IkeruTheme.Spacing.xs) {
                    Text("Meet Sakura")
                        .ikeruScaledFont(26, weight: .light, design: .serif, relativeTo: .title2)
                        .foregroundStyle(Color.ikeruTextPrimary)

                    Text("Your Japanese conversation partner")
                        .ikeruScaledFont(14, weight: .regular, relativeTo: .body)
                        .foregroundStyle(Color.ikeruTextSecondary)

                    // JLPT level badge — encre rectangle, no capsule
                    Text(viewModel.jlptLevel.displayName)
                        .ikeruScaledFont(11, weight: .semibold, relativeTo: .caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.ikeruPrimaryAccent)
                        .tracking(1.4)
                        .padding(.horizontal, IkeruTheme.Spacing.sm)
                        .padding(.vertical, IkeruTheme.Spacing.xs)
                        .overlay(
                            Rectangle()
                                .strokeBorder(TatamiTokens.goldDim, lineWidth: 1)
                        )
                        .padding(.top, IkeruTheme.Spacing.xs)
                }
                .multilineTextAlignment(.center)

                // Suggestion chips — rectangle + sumi corners, not Capsule.
                // Level- and language-aware: a beginner (N5) gets simple openers
                // in their own language; from N4 up, short Japanese openers.
                VStack(spacing: IkeruTheme.Spacing.sm) {
                    ForEach(starters(for: viewModel.jlptLevel, locale: locale)) { starter in
                        suggestionButton(starter)
                    }
                }

                Spacer(minLength: IkeruTheme.Spacing.xl)
            }
            .padding(.horizontal, IkeruTheme.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Suggestion Button

    /// Affiche le japonais, et sous lui sa glose quand il y en a une — c'est
    /// le japonais qui part (OBS2-030). Un débutant peut donc envoyer une
    /// vraie phrase japonaise sans la comprendre à l'aveugle.
    private func suggestionButton(_ starter: ChatStarter) -> some View {
        Button {
            Task { await viewModel.sendMessage(starter.sent) }
        } label: {
            VStack(spacing: 2) {
                Text(starter.sent)
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
                if let gloss = starter.gloss {
                    Text(gloss)
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextTertiary)
                }
            }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.vertical, IkeruTheme.Spacing.sm)
                .background(
                    Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.07)
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(TatamiTokens.goldDim.opacity(0.5), lineWidth: 1)
                )
                .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Starter Chips

    /// Une amorce : `sent` est ce qui part à Sakura, `gloss` ce qu'on affiche
    /// dessous pour que l'apprenant sache ce qu'il envoie.
    private struct ChatStarter: Identifiable {
        let sent: String
        let gloss: String?
        var id: String { sent }
    }

    /// Amorces de conversation, en JAPONAIS à tous les niveaux (OBS2-030).
    ///
    /// Au N5 elles étaient rédigées dans la langue de l'apprenant — « Bonjour !
    /// Comment ça va ? » — sur un écran dont le champ de saisie invite à
    /// « Écris en japonais… ». L'intention était bonne (ne pas bloquer
    /// quelqu'un qui ne sait pas encore lire) mais elle contredisait
    /// l'invitation, et surtout elle privait le débutant du seul moment où on
    /// lui met une phrase japonaise correcte dans la main.
    ///
    /// Les puces N5 portent donc la phrase japonaise ET sa traduction : le
    /// japonais part, la glose reste sous les yeux. On ne demande pas de
    /// comprendre pour envoyer, on montre ce qu'on envoie. À partir du N4 la
    /// glose disparaît — la phrase se lit toute seule.
    private func starters(for level: JLPTLevel, locale: Locale) -> [ChatStarter] {
        if level == .n5 {
            let isFrench = locale.language.languageCode?.identifier == "fr"
            let glosses = isFrench
                ? ["Bonjour ! Comment ça va ?",
                   "J'apprends le japonais.",
                   "Apprends-moi un mot, s'il te plaît."]
                : ["Hello! How are you?",
                   "I'm learning Japanese.",
                   "Please teach me a word."]
            let japanese = [
                "こんにちは！お元気ですか？",
                "日本語を勉強しています。",
                "単語を教えてください。"
            ]
            return zip(japanese, glosses).map { ChatStarter(sent: $0, gloss: $1) }
        }
        return ["こんにちは！", "今日は何をしましたか？", "趣味について話しましょう。"]
            .map { ChatStarter(sent: $0, gloss: nil) }
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
            .scrollClipDisabled()
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
            .background(
                Rectangle()
                    .fill(Color(red: 0.102, green: 0.102, blue: 0.133).opacity(0.78))
            )
            .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)

            Spacer()
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            // Encre warning mark — no pink/rose icon
            Text("—")
                .ikeruScaledFont(14, weight: .semibold, design: .serif, relativeTo: .body)
                .foregroundStyle(Color.ikeruPrimaryAccent)

            // message is a catalogue KEY (resolved via the injected \.locale so
            // it honours the in-app language); unknown keys fall back to verbatim.
            Text(LocalizedStringKey(message))
                .font(.ikeruCaption)
                .foregroundStyle(.ikeruTextSecondary)

            Spacer()

            Button("Retry") {
                Task { await viewModel.retryLastMessage() }
            }
            .font(.ikeruCaption)
            .fontWeight(.semibold)
            .foregroundStyle(Color.ikeruPrimaryAccent)
        }
        .padding(IkeruTheme.Spacing.sm)
        .background(
            Rectangle()
                .fill(Color(red: 0.102, green: 0.086, blue: 0.071).opacity(0.82))
        )
        .overlay(alignment: .top) {
            Rectangle().fill(TatamiTokens.goldDim.opacity(0.5)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(TatamiTokens.goldDim.opacity(0.3)).frame(height: 1)
        }
        .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            FusumaRail(gold: TatamiTokens.goldDim, opacity: 0.6)

            HStack(spacing: IkeruTheme.Spacing.sm) {
                voiceButton

                TextField("Type in Japanese...", text: $viewModel.inputText, axis: .vertical)
                    .font(.ikeruBody)
                    .foregroundStyle(.white)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, IkeruTheme.Spacing.sm)
                    .padding(.vertical, IkeruTheme.Spacing.sm)
                    .background(
                        Rectangle()
                            .fill(Color(red: 0.102, green: 0.102, blue: 0.133).opacity(0.82))
                    )
                    .sumiCorners(color: TatamiTokens.goldDim, size: 5, weight: 0.9)
                    .onSubmit {
                        Task { await viewModel.sendMessage() }
                    }

                sendButton
            }
            .padding(.horizontal, IkeruTheme.Spacing.md)
            .padding(.vertical, IkeruTheme.Spacing.sm)
            .background(Color.ikeruBackground.opacity(0.95))
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
                        ? Color.ikeruPrimaryAccent
                        : .ikeruTextSecondary
                )
                .frame(width: 36, height: 36)
                .background(
                    viewModel.isVoiceActive
                        ? Color.ikeruPrimaryAccent.opacity(0.15)
                        : Color.clear
                )
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
        Menu {
            Picker("Sakura.Level.Picker", selection: $viewModel.jlptLevel) {
                ForEach(JLPTLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
        } label: {
            Text(viewModel.jlptLevel.displayName)
                .font(.ikeruCaption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.ikeruPrimaryAccent)
                .padding(.horizontal, IkeruTheme.Spacing.sm)
                .padding(.vertical, IkeruTheme.Spacing.xs)
                .overlay(
                    Rectangle()
                        .strokeBorder(TatamiTokens.goldDim, lineWidth: 1)
                )
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color(hex: IkeruTheme.Colors.primaryAccent).opacity(0.6))
            .frame(width: 8, height: 8)
            // Reduce Motion: three static dots still read as "typing…" without
            // the bouncing loop.
            .offset(y: reduceMotion ? 0 : (isAnimating ? -4 : 0))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.5)
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
