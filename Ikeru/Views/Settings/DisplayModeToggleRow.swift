import SwiftUI
import IkeruCore

/// Settings row for the `Interface Tatami` toggle. Reads/writes the active
/// profile's `DisplayMode` through the repository in environment.
struct DisplayModeToggleRow: View {

    let repository: any DisplayModePreferenceRepository

    /// Kept live by `MainTabView` on every profile switch/create/delete (see
    /// `.displayModeDidChange`) as well as on an explicit toggle. `isTatamiOn`
    /// mirrors it below so the switch reflects the *active* profile instead
    /// of whichever profile was active when this row was first initialized.
    @Environment(\.displayMode) private var activeDisplayMode
    @State private var isTatamiOn: Bool

    init(repository: any DisplayModePreferenceRepository) {
        self.repository = repository
        _isTatamiOn = State(initialValue: repository.current() == .tatami)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text("畳")
                    .ikeruScaledFont(13, design: .serif, relativeTo: .caption)
                    .foregroundStyle(TatamiTokens.paperGhost)
                Text("Settings.InterfaceTatami.Title")
                    .ikeruScaledFont(13, relativeTo: .caption)
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
                .foregroundStyle(Color.ikeruTextSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .onChange(of: isTatamiOn) { _, new in
            repository.set(new ? .tatami : .beginner)
        }
        .onChange(of: activeDisplayMode) { _, new in
            let onValue = new == .tatami
            if isTatamiOn != onValue {
                isTatamiOn = onValue
            }
        }
    }
}
