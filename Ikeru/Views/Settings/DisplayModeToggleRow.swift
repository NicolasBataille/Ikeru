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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings.InterfaceTatami.Title")
                        .font(.ikeruHeading3)
                        .foregroundStyle(Color.ikeruTextPrimary)
                    Text("Settings.InterfaceTatami.Subtitle")
                        .font(.ikeruCaption)
                        .foregroundStyle(Color.ikeruTextSecondary)
                }
                Spacer()
                Toggle("", isOn: $isTatamiOn)
                    .labelsHidden()
                    .tint(Color.ikeruPrimaryAccent)
            }
            Text(isTatamiOn
                 ? "Settings.InterfaceTatami.HelpOn"
                 : "Settings.InterfaceTatami.HelpOff")
                .font(.ikeruCaption)
                .foregroundStyle(TatamiTokens.paperGhost)
        }
        .onChange(of: isTatamiOn) { _, new in
            repository.set(new ? .tatami : .beginner)
        }
    }
}
