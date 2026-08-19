import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import IkeruCore

// MARK: - TextImportCaptureView

/// La première porte de « apporte ton propre texte » : coller, taper, ou
/// photographier.
///
/// ## Une seule zone de texte, jamais deux modes
///
/// Le texte reconnu par l'appareil photo atterrit dans **le même champ** que le
/// texte collé, et y reste éditable. La vision est explicite : « la correction
/// est un moment d'apprentissage, pas une corvée cachée ». Un écran « voici ce
/// que j'ai lu, valide ou recommence » ferait de la correction un mode à part ;
/// ici c'est une édition ordinaire.
///
/// ## L'OCR n'est pas fait ici
///
/// La reconnaissance est le chantier d'à côté. Cette vue prend une fermeture et
/// se contente d'afficher son résultat — ce qui garde `Vision` hors de ce
/// fichier et rend l'écran utilisable sans appareil photo.
struct TextImportCaptureView: View {

    @Bindable var viewModel: TextImportViewModel

    /// Reconnaît le japonais d'une image encodée (JPEG/PNG/HEIC).
    ///
    /// Contrat : renvoyer le texte lu tel quel, ou lever une
    /// `TextRecognitionError` — dont le `messageKey` est affiché à
    /// l'utilisateur. Une chaîne vide est traitée comme
    /// `.noHorizontalTextFound` : c'est la même chose vue de l'écran. Ne jamais
    /// renvoyer un texte inventé ou « corrigé » — ce qui sort d'ici devient le
    /// texte de l'utilisateur, et il en garde la main.
    ///
    /// Par défaut : le service embarqué (`TextRecognitionService`), 100 %
    /// hors ligne. Le paramètre existe pour l'injecter autrement — aperçus,
    /// tests, ou un moteur différent plus tard.
    ///
    /// Isolée sur le `MainActor` parce que l'appelant l'est : la fermeture peut
    /// capturer aussi bien un service `MainActor` qu'un acteur de fond, sans
    /// contrainte `Sendable` sur le site d'appel.
    var onRecognizeImage: @MainActor (Data) async throws -> String = TextImportCaptureView.recognizeOnDevice

    @State private var photoItem: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var isRecognizing = false
    /// Clé de catalogue du dernier échec de reconnaissance, `nil` sinon.
    /// C'est `TextRecognitionError.messageKey` qui la fournit : le message sur
    /// le texte vertical appartient au service qui l'a mesuré, pas à l'écran.
    @State private var recognitionErrorKey: String?
    @State private var pasteboardWasEmpty = false
    /// Vrai quand l'accès à l'appareil photo a été refusé (ou est restreint).
    /// `UIImagePickerController` ne prévient de rien dans ce cas : il se
    /// présente et affiche un aperçu noir. On l'intercepte avant.
    @State private var cameraAccessDenied = false
    @FocusState private var isEditing: Bool

    private var trimmedDraft: String {
        viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAnalyze: Bool {
        !trimmedDraft.isEmpty && !viewModel.isAnalyzing && !isRecognizing
    }

    var body: some View {
        ZStack {
            IkeruScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: IkeruTheme.Spacing.lg) {
                    header
                    editor
                    sourceButtons
                    statusMessages
                    analyzeButton
                    Spacer(minLength: IkeruTheme.Spacing.xxl)
                }
                .padding(.horizontal, IkeruTheme.Spacing.md)
                .padding(.top, IkeruTheme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("TextImport.Capture.Title")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadFromLibrary(item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            TextImportCameraPicker(
                onCapture: { data in
                    showCamera = false
                    Task { await recognize(data) }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
            Text("TextImport.Capture.Kicker")
                .font(.ikeruMicro)
                .ikeruTracking(.micro)
                .foregroundStyle(Color.ikeruTextTertiary)
            Text("TextImport.Capture.Subtitle")
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Editor

    /// Le champ est la source de vérité du brouillon : rien ne le réécrit dans
    /// le dos de l'utilisateur, et le texte reconnu s'y **ajoute** au lieu de
    /// l'effacer.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.draft)
                .font(.ikeruBodyLarge)
                .foregroundStyle(Color.ikeruTextPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .padding(IkeruTheme.Spacing.sm)
                .focused($isEditing)
                .autocorrectionDisabled()
                .accessibilityLabel("TextImport.Capture.Field")

            if viewModel.draft.isEmpty {
                Text("TextImport.Capture.Placeholder")
                    .font(.ikeruBody)
                    .foregroundStyle(Color.ikeruTextTertiary)
                    .padding(.horizontal, IkeruTheme.Spacing.sm + 5)
                    .padding(.vertical, IkeruTheme.Spacing.sm + 8)
                    .allowsHitTesting(false)
            }
        }
        .background {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.35), lineWidth: 0.5) }
        }
        .sumiCorners(color: TatamiTokens.goldDim, size: 7, weight: 1.0)
    }

    // MARK: - Source buttons

    private var sourceButtons: some View {
        HStack(spacing: IkeruTheme.Spacing.sm) {
            sourceButton(icon: "doc.on.clipboard", label: "TextImport.Capture.Paste") {
                pasteFromClipboard()
            }
            sourceButton(icon: "photo.on.rectangle", label: "TextImport.Capture.Library") {
                showLibrary = true
            }
            // Le simulateur n'a pas d'appareil photo : sans ce garde, le bouton
            // existerait et ne ferait rien. Attention, ce test porte sur le
            // MATÉRIEL, pas sur l'autorisation — d'où le contrôle séparé au tap.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                sourceButton(icon: "camera", label: "TextImport.Capture.Camera") {
                    Task { await presentCameraIfAllowed() }
                }
            }
        }
    }

    private func sourceButton(icon: String,
                              label: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .light))
                Text(label)
                    .ikeruScaledFont(11, weight: .medium, relativeTo: .caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.ikeruPrimaryAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, IkeruTheme.Spacing.sm)
            .background {
                Rectangle()
                    .fill(Color.ikeruPrimaryAccent.opacity(0.10))
                    .overlay { Rectangle().strokeBorder(TatamiTokens.goldDim.opacity(0.45), lineWidth: 0.5) }
            }
            .sumiCorners(color: TatamiTokens.goldDim, size: 6, weight: 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isRecognizing)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusMessages: some View {
        if isRecognizing {
            noticeRow(icon: "text.viewfinder",
                      tint: Color.ikeruTextSecondary,
                      message: "TextImport.Capture.Recognizing",
                      showsSpinner: true)
        }

        // On ne dit pas « échec » : la reconnaissance sur l'appareil lit
        // l'imprimé horizontal et rend zéro caractère sur le vertical des
        // bulles de manga — c'est mesuré, et c'est ce que dit
        // `import.photo.error.verticalNotSupported`. Nommer la vraie limite,
        // c'est ce qui permet de décider quoi faire ensuite : taper le texte.
        if let recognitionErrorKey {
            noticeRow(icon: "character.textbox",
                      tint: Color.ikeruWarning,
                      message: LocalizedStringKey(recognitionErrorKey))
        }

        // Refus d'accès : `UIImagePickerController` présenté sans autorisation
        // affiche un aperçu noir muet. On dit ce qui manque, et où le réparer.
        if cameraAccessDenied {
            VStack(alignment: .leading, spacing: IkeruTheme.Spacing.xs) {
                noticeRow(icon: "camera",
                          tint: Color.ikeruWarning,
                          message: "TextImport.Capture.CameraDenied")
                Button("Open Settings") { openSettings() }
                    .font(.ikeruCaption)
                    .foregroundStyle(Color.ikeruPrimaryAccent)
            }
        }

        if pasteboardWasEmpty {
            noticeRow(icon: "doc.on.clipboard",
                      tint: Color.ikeruTextSecondary,
                      message: "TextImport.Capture.ClipboardEmpty")
        }

        // `dictionaryAvailable` ne passe à faux qu'après une tentative : c'est
        // `analyzeDraft()` qui interroge le dictionnaire. On rend l'état quand
        // il est faux, sans inventer une pré-vérification qui n'existe pas.
        if !viewModel.dictionaryAvailable {
            noticeRow(icon: "exclamationmark.triangle",
                      tint: Color.ikeruDanger,
                      message: "TextImport.Capture.DictionaryUnavailable")
        }
    }

    private func noticeRow(icon: String,
                           tint: Color,
                           message: LocalizedStringKey,
                           showsSpinner: Bool = false) -> some View {
        HStack(alignment: .top, spacing: IkeruTheme.Spacing.sm) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .tint(tint)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(tint)
            }
            Text(message)
                .font(.ikeruCaption)
                .foregroundStyle(Color.ikeruTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(IkeruTheme.Spacing.sm)
        .background {
            Rectangle()
                .fill(tint.opacity(0.08))
                .overlay { Rectangle().strokeBorder(tint.opacity(0.35), lineWidth: 0.5) }
        }
        .sumiCorners(color: tint.opacity(0.7), size: 5, weight: 0.9)
    }

    // MARK: - Analyze

    private var analyzeButton: some View {
        Button {
            isEditing = false
            Task { await viewModel.analyzeDraft() }
        } label: {
            HStack(spacing: IkeruTheme.Spacing.xs) {
                if viewModel.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.ikeruBackground)
                    Text("TextImport.Capture.Analyzing")
                } else {
                    Text("TextImport.Capture.Analyze")
                }
            }
        }
        .ikeruButtonStyle(.primary)
        .disabled(!canAnalyze)
        .opacity(canAnalyze ? 1 : 0.45)
        .accessibilityIdentifier("textImport.analyze")
    }

    // MARK: - Actions

    /// Ouvre l'appareil photo **seulement** si l'accès est accordé.
    ///
    /// `UIImagePickerController.isSourceTypeAvailable(.camera)` répond sur le
    /// matériel, pas sur l'autorisation : sur un téléphone où l'accès a été
    /// refusé, le bouton existe, la vue plein écran se présente, et
    /// l'utilisateur regarde un rectangle noir sans savoir pourquoi. Le refus
    /// est un état à nommer, pas un écran vide.
    private func presentCameraIfAllowed() async {
        cameraAccessDenied = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            // Demander nous-mêmes plutôt que de laisser le picker le faire :
            // sinon un refus au moment du prompt laisse le picker présenté sur
            // un aperçu noir.
            if await AVCaptureDevice.requestAccess(for: .video) {
                showCamera = true
            } else {
                cameraAccessDenied = true
            }
        default:
            cameraAccessDenied = true
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Colle le presse-papiers. Quand le champ contient déjà quelque chose, le
    /// texte s'ajoute : effacer ce que l'utilisateur a tapé serait réécrire son
    /// texte, ce que cette feature ne fait jamais.
    private func pasteFromClipboard() {
        pasteboardWasEmpty = false
        recognitionErrorKey = nil
        cameraAccessDenied = false
        let clipboard = (UIPasteboard.general.string ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipboard.isEmpty else {
            pasteboardWasEmpty = true
            return
        }
        viewModel.begin(with: merged(with: clipboard), source: .paste)
    }

    private func loadFromLibrary(_ item: PhotosPickerItem) async {
        photoItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            recognitionErrorKey = TextRecognitionError.imageUnreadable.messageKey
            return
        }
        await recognize(data)
    }

    private func recognize(_ data: Data) async {
        pasteboardWasEmpty = false
        recognitionErrorKey = nil
        cameraAccessDenied = false
        isRecognizing = true
        defer { isRecognizing = false }

        do {
            let recognized = try await onRecognizeImage(data)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Un résultat vide est la même chose que « rien reconnu » vue de
            // l'écran : on ne montre jamais un « résultat » vide.
            guard !recognized.isEmpty else {
                recognitionErrorKey = TextRecognitionError.noHorizontalTextFound.messageKey
                return
            }
            viewModel.begin(with: merged(with: recognized), source: .photo)
        } catch let error as TextRecognitionError {
            recognitionErrorKey = error.messageKey
        } catch {
            recognitionErrorKey = TextRecognitionError.recognitionFailed("").messageKey
        }
    }

    // MARK: - Reconnaissance par défaut

    /// Adaptateur vers le service embarqué : lui passer les octets tels quels
    /// et le laisser faire le travail — y compris lire l'orientation EXIF du
    /// fichier et décider que « rien de lisible » se dit
    /// `noHorizontalTextFound`.
    ///
    /// L'orientation n'est pas cosmétique : `VNImageRequestHandler` reçoit un
    /// `CGImage` nu, sans EXIF, donc une photo prise en portrait arriverait
    /// couchée et ne serait pas lue — et l'écran accuserait « texte vertical »
    /// une page parfaitement horizontale. C'est exactement ce que la surcharge
    /// `recognizeText(in: Data)` prend en charge, en lisant le tag sur la
    /// source ImageIO. Passer par elle plutôt que de redresser ici évite en
    /// prime de redessiner une image de 12 Mpx sur le `MainActor`.
    static func recognizeOnDevice(_ data: Data) async throws -> String {
        try await TextRecognitionService().recognizeText(in: data).text
    }

    /// Passer par `begin(with:source:)` plutôt que d'écrire `draft` directement :
    /// c'est lui qui porte la provenance. Sans ça, un texte photographié serait
    /// enregistré dans le journal comme collé.
    private func merged(with addition: String) -> String {
        trimmedDraft.isEmpty ? addition : viewModel.draft + "\n" + addition
    }
}

// MARK: - TextImportCameraPicker

/// Pont minimal vers `UIImagePickerController` : SwiftUI n'expose pas de prise
/// de vue photo native en iOS 17, et `ShareSheet` est le précédent maison pour
/// ce genre d'enveloppe.
private struct TextImportCameraPicker: UIViewControllerRepresentable {

    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        private let onCapture: (Data) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else {
                onCancel()
                return
            }
            onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
