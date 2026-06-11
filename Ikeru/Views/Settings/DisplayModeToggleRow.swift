import SwiftUI
import IkeruCore

/// Settings row for the `Interface Tatami` toggle. Reads/writes the active
/// profile's `DisplayMode` through the repository in environment.
struct DisplayModeToggleRow: View {

    let repository: any DisplayModePreferenceRepository
    @State private var isTatamiOn: Bool

    init(repository: any DisplayModePreferenceRepository) {
        self.repository = repository
        _isTatamiOn = State(initialValue: repository.current() == .tatami)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text("畳")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text("Settings.InterfaceTatami.Title")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ikeruTextPrimary)
                Spacer()
                TatamiToggle(isOn: $isTatamiOn) { _ in }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(TatamiTokens.goldDim.opacity(0.2))
                    .frame(height: 1).padding(.horizontal, 16)
            }

            Text(isTatamiOn
                 ? "Settings.InterfaceTatami.HelpOn"
                 : "Settings.InterfaceTatami.HelpOff")
                .font(.ikeruCaption)
                .foregroundStyle(TatamiTokens.paperGhost)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .onChange(of: isTatamiOn) { _, new in
            repository.set(new ? .tatami : .beginner)
        }
    }
}
