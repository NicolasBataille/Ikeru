import SwiftUI
import IkeruCore
import os

// MARK: - NameEntryView

struct NameEntryView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.profileViewModel) private var profileViewModel
    @State private var name: String = ""
    @State private var showTour = false
    @State private var contentAppeared = false
    @FocusState private var isNameFieldFocused: Bool

    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            VStack(spacing: 0) {
                Spacer()

                heroBlock
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 16)

                Spacer().frame(height: IkeruTheme.Spacing.xxl)

                nameInputSection
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 16)

                Spacer().frame(height: IkeruTheme.Spacing.xl)

                continueButton
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 16)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, IkeruTheme.Spacing.xl)
        }
        .fullScreenCover(isPresented: $showTour, onDismiss: {
            dismiss()
        }) {
            OnboardingTourView()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.86).delay(0.1)) {
                contentAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isNameFieldFocused = true
            }
        }
    }

    // MARK: - Hero block

    private var heroBlock: some View {
        VStack(spacing: IkeruTheme.Spacing.md) {
            // Japanese kanji ornament
            Text("\u{4E2D}")
                .font(.kanjiHero)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xF5DBB6),
                            Color(hex: 0xD4A574),
                            Color(hex: 0xB88A5C)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(hex: 0xD4A574, opacity: 0.4), radius: 32)

            VStack(spacing: 8) {
                Text("YOUR JOURNEY BEGINS")
                    .font(.ikeruMicro)
                    .ikeruTracking(.micro)
                    .foregroundStyle(Color.ikeruTextTertiary)

                Text("What should\nwe call you?")
                    .font(.system(size: 36, weight: .light))
                    .ikeruTracking(.display)
                    .foregroundStyle(Color.ikeruTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Name Input

    private var nameInputSection: some View {
        TextField(
            "",
            text: $name,
            prompt: Text("Your name").foregroundStyle(Color.ikeruTextTertiary)
        )
        .font(.system(size: 22, weight: .regular))
        .foregroundStyle(Color.ikeruTextPrimary)
        .multilineTextAlignment(.center)
        .padding(.vertical, IkeruTheme.Spacing.md)
        .padding(.horizontal, IkeruTheme.Spacing.lg)
        .background {
            IkeruGlassSurface(
                cornerRadius: IkeruTheme.Radius.lg,
                tint: isNameFieldFocused ? .ikeruPrimaryAccent : .clear,
                tintOpacity: isNameFieldFocused ? 0.10 : 0.0,
                strokeOpacity: isNameFieldFocused ? 0.30 : 0.18,
                strokeWidth: isNameFieldFocused ? 1.0 : 0.6
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: IkeruTheme.Radius.lg, style: .continuous))
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isNameFieldFocused)
        .focused($isNameFieldFocused)
        .submitLabel(.continue)
        .onSubmit { submitName() }
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            submitName()
        } label: {
            HStack(spacing: 10) {
                Text("Continue")
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .ikeruButtonStyle(.primary)
        .disabled(!isNameValid)
        .opacity(isNameValid ? 1.0 : 0.45)
        .scaleEffect(isNameValid ? 1.0 : 0.98)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isNameValid)
    }

    // MARK: - Actions

    private func submitName() {
        guard isNameValid else { return }
        Logger.ui.info("Name submitted for profile creation")
        profileViewModel?.createProfile(name: name)
        showTour = true
    }
}

// MARK: - Preview

#Preview("NameEntryView") {
    NameEntryView()
        .preferredColorScheme(.dark)
}
