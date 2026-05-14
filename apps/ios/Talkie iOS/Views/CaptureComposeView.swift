//
//  CaptureComposeView.swift
//  Talkie iOS
//
//  Unified creation screen for captures.
//  Primary: text area + dictation mic. Secondary: camera, photo library, URL import.
//  Import options fade away once composing begins.
//

import SwiftUI
import PhotosUI
import TalkieMobileKit
import VisionKit

struct CaptureComposeView: View {
    /// Optional URL to open directly in the web browser
    var initialURL: URL?
    var onCaptureSaved: ((Capture) -> Void)?

    // MARK: - Draft state
    @State private var draftText = ""
    @State private var isComposing = false
    @FocusState private var isDraftFocused: Bool

    // MARK: - Dictation state
    @State private var dictationState: InlineDictationController.State = .idle
    @State private var dictationError: String?
    @State private var dictationTrigger = 0
    @State private var dictationResetTrigger = 0

    // MARK: - Import state
    @State private var showingCamera = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isRunningOCR = false
    @State private var showingWebBrowser = false
    @State private var webBrowserURL: URL?
    @State private var importedImage: UIImage?
    @State private var importedImageData: Data?
    @State private var importedPageCount = 0
    @State private var importedDidDetectPage = false
    @State private var importedSourceURL: String?
    @State private var importError: String?
    @State private var deferredPageURLs: [URL] = []

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    // Imported image thumbnail
                    if let image = importedImage {
                        importedImageThumbnail(image)
                    }

                    // Editor card — always present
                    ComposeEditorCard(
                        placeholder: "Start typing or dictate...",
                        editorMinHeight: isComposing ? 300 : 140,
                        text: $draftText,
                        draftFocus: $isDraftFocused,
                        dictationState: $dictationState,
                        dictationError: $dictationError,
                        dictationTrigger: $dictationTrigger,
                        dictationResetTrigger: $dictationResetTrigger
                    ) {
                        EmptyView()
                    }
                    .animation(.easeInOut(duration: 0.25), value: isComposing)

                    // Import options — hidden when composing
                    if !isComposing {
                        importOptionsSection
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .animation(.easeInOut(duration: 0.25), value: isComposing)
            .navigationTitle("New Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCapture() }
                        .fontWeight(.semibold)
                        .disabled(trimmedText.isEmpty)
                }
            }
            .sheet(isPresented: $showingCamera) {
                if supportsDocumentScanner {
                    DocumentCameraScannerView(
                        onPageScanned: processFirstPage(_:deferredPages:),
                        onFailure: { message in
                            importError = message
                        }
                    )
                } else {
                    CameraImagePicker { image in
                        processFirstPage(image, deferredPages: [])
                    }
                }
            }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $photoPickerItems,
                maxSelectionCount: 1,
                matching: .images
            )
            .onChange(of: photoPickerItems) { _, items in
                guard let item = items.first else { return }
                loadPhotoPickerItem(item)
            }
            .onChange(of: isDraftFocused) { _, focused in
                if focused && !isComposing {
                    withAnimation { isComposing = true }
                }
                if !focused && trimmedText.isEmpty && importedImage == nil {
                    withAnimation { isComposing = false }
                }
            }
            .onChange(of: draftText) { _, text in
                let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if hasContent && !isComposing {
                    withAnimation { isComposing = true }
                }
            }
            .onChange(of: dictationState) { _, state in
                if state == .recording && !isComposing {
                    withAnimation { isComposing = true }
                }
            }
            .fullScreenCover(isPresented: $showingWebBrowser) {
                WebCaptureBrowser(initialURL: webBrowserURL) { result in
                    draftText = result.text
                    importedSourceURL = result.url
                    withAnimation { isComposing = true }
                }
            }
            .onAppear {
                if let url = initialURL {
                    webBrowserURL = url
                    showingWebBrowser = true
                }
            }
        }
    }

    // MARK: - Import Options

    @State private var showingPhotoPicker = false

    private var importOptionsSection: some View {
        VStack(spacing: Spacing.sm) {
            Text("OR IMPORT FROM")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Camera + Photo Library row
            HStack(spacing: Spacing.sm) {
                AttachmentPickerActionCard(
                    icon: "camera.fill",
                    title: "Scan Pages",
                    subtitle: "Detect page edges live",
                    tint: .textSecondary,
                    action: startCameraImport
                )

                AttachmentPickerActionCard(
                    icon: "photo.on.rectangle",
                    title: "Photo Library",
                    subtitle: "Choose an image",
                    tint: .textSecondary,
                    action: { showingPhotoPicker = true }
                )
            }

            // Web browse + capture
            AttachmentPickerActionCard(
                icon: "safari",
                title: "Browse Web",
                subtitle: "Find and capture a web page",
                tint: .textSecondary,
                action: { showingWebBrowser = true }
            )

            // Error display
            if let error = importError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Imported Image Thumbnail

    private func importedImageThumbnail(_ image: UIImage) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(importedImageStatusTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)

                if isRunningOCR {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let subtitle = importedImageStatusSubtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            if !deferredPageURLs.isEmpty && !isRunningOCR {
                Button(action: ocrRemainingOnDevice) {
                    Text("OCR on device")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation {
                    importedImage = nil
                    importedImageData = nil
                    importedPageCount = 0
                    importedDidDetectPage = false
                    cleanupDeferredPages()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.sm)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    // MARK: - Actions

    private var supportsDocumentScanner: Bool {
        DocumentCameraScannerView.isSupported
    }

    private var supportsCameraCapture: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var importedImageStatusTitle: String {
        if isRunningOCR {
            return "Scanning page..."
        }

        if !deferredPageURLs.isEmpty {
            let scanned = importedPageCount - deferredPageURLs.count
            return "Page \(scanned) of \(importedPageCount) scanned"
        }

        if importedPageCount > 1 {
            return "\(importedPageCount) pages scanned"
        }

        if importedDidDetectPage {
            return "Page detected"
        }

        return "Image attached"
    }

    private var importedImageStatusSubtitle: String? {
        if !deferredPageURLs.isEmpty {
            return "\(deferredPageURLs.count) pages waiting"
        }

        if importedPageCount > 1 {
            return "All pages scanned"
        }

        if importedDidDetectPage {
            return "Perspective corrected for OCR"
        }

        return nil
    }

    private func startCameraImport() {
        guard supportsDocumentScanner || supportsCameraCapture else {
            importError = "Camera capture is not available on this device."
            return
        }

        showingCamera = true
    }

    private func processFirstPage(_ image: UIImage, deferredPages: [URL]) {
        importedImage = image
        importedImageData = image.jpegData(compressionQuality: 0.8)
        importedPageCount = 1 + deferredPages.count
        importedDidDetectPage = true
        importedSourceURL = nil
        deferredPageURLs = deferredPages

        Task {
            isRunningOCR = true
            importError = nil
            defer { isRunningOCR = false }

            do {
                let result = try await ScreenshotOCRService.extractText(from: image)
                importedImage = result.image
                importedImageData = result.image.jpegData(compressionQuality: 0.8)
                importedDidDetectPage = result.didDetectPage

                if !result.text.isEmpty {
                    draftText = result.text
                    withAnimation { isComposing = true }
                } else {
                    importError = "No text detected in image"
                }
            } catch {
                importError = "OCR failed: \(error.localizedDescription)"
            }
        }
    }

    private func cleanupDeferredPages() {
        for url in deferredPageURLs {
            try? FileManager.default.removeItem(at: url)
        }
        deferredPageURLs = []
    }

    private func ocrRemainingOnDevice() {
        let urls = deferredPageURLs
        guard !urls.isEmpty else { return }

        Task {
            isRunningOCR = true
            defer { isRunningOCR = false }

            for url in urls {
                do {
                    let loadedImage: UIImage? = autoreleasepool {
                        guard let data = try? Data(contentsOf: url) else { return nil }
                        return UIImage(data: data)
                    }
                    guard let loadedImage else { continue }

                    let result = try await ScreenshotOCRService.extractText(from: loadedImage)
                    if !result.text.isEmpty {
                        draftText += "\n\n" + result.text
                    }
                } catch {
                    // Skip pages that fail OCR
                }

                try? FileManager.default.removeItem(at: url)
                deferredPageURLs.removeAll { $0 == url }
            }
        }
    }

    private func loadPhotoPickerItem(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                importError = "Could not load image"
                return
            }
            processFirstPage(image, deferredPages: [])
        }
    }

    private func saveCapture() {
        guard !trimmedText.isEmpty else { return }

        let captureId = UUID()

        // Save image if we have one
        var imageFilename: String?
        if let imageData = importedImageData {
            imageFilename = CaptureStore.shared.saveImage(imageData, id: captureId)
        }

        // Persist deferred pages (lossless PNGs) to CaptureStore
        var deferredFilenames: [String] = []
        for (index, url) in deferredPageURLs.enumerated() {
            if let data = try? Data(contentsOf: url),
               let filename = CaptureStore.shared.saveDeferredPage(data, captureId: captureId, pageIndex: index + 1) {
                deferredFilenames.append(filename)
            }
            try? FileManager.default.removeItem(at: url)
        }
        deferredPageURLs = []

        let sourceType: String = {
            if imageFilename != nil { return "photo" }
            if importedSourceURL != nil { return "url" }
            return "text"
        }()

        let capture = Capture(
            id: captureId,
            sourceType: sourceType,
            text: trimmedText,
            sourceURL: importedSourceURL,
            imageFilename: imageFilename,
            deferredPageFilenames: deferredFilenames.isEmpty ? nil : deferredFilenames,
            totalPageCount: importedPageCount > 1 ? importedPageCount : nil
        )

        onCaptureSaved?(capture)
        dismiss()
    }

    private var trimmedText: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
