import SwiftUI
import IkeruCore
import os

// MARK: - NameEntryView

struct NameEntryView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.profileViewModel) private var profileViewModel
    @State private var name: String = ""
    @State private var showTour = false
    @FocusState private var isNameFieldFocused: Bool

    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.ikeruBackground
                .ignoresSafeArea()

            VStack(spacing: IkeruTheme.Spacing.xl) {
                Spacer()

                headerSection

                nameInputSection

                continueButton

                Spacer()
                Spacer()
            }
            .padding(.horizontal, IkeruTheme.Spacing.lg)
        }
        .fullScreenCover(isPresented: $showTour, onDismiss: {
            // Tour finished — dismiss the entire onboarding flow
            dismiss()
        }) {
            OnboardingTourView()
        }
        .onAppear {
            isNameFieldFocused = true
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: IkeruTheme.Spacing.sm) {
            Text("Your adventure begins")
                .font(.ikeruHeading1)
                .foregroundStyle(.white)

            Text("What should we call you?")
                .font(.ikeruBody)
                .foregroundStyle(.ikeruTextSecondary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Name Input

    private var nameInputSection: some View {
        TextField("", text: $name, prompt: Text("Your name")
            .foregroundStyle(.ikeruTextSecondary))
            .font(.system(size: IkeruTheme.Typography.Size.heading2, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(IkeruTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                    .fill(Color.ikeruSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IkeruTheme.Radius.md)
                    .strokeBorder(
                        isNameFieldFocused
                            ? Color.ikeruPrimaryAccent
                            : Color.clear,
                        lineWidth: 2
                    )
            )
            .focused($isNameFieldFocused)
            .submitLabel(.continue)
            .onSubmit {
                submitName()
            }
            .padding(.horizontal, IkeruTheme.Spacing.lg)
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button("Continue") {
            submitName()
        }
        .ikeruButtonStyle(.primary)
        .disabled(!isNameValid)
        .opacity(isNameValid ? 1.0 : 0.5)
        .padding(.horizontal, IkeruTheme.Spacing.lg)
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
