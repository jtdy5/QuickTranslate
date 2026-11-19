import SwiftUI
import UIKit
import PhotosUI
import Vision
import Translation
import ImageIO
import NaturalLanguage
import QuickLook

struct RecognizedLine: Identifiable {
    let id = UUID()
    let text: String
    let box: CGRect
    let confidence: Float
    let pixelRect: CGRect
    let glyphRects: [CGRect]
}

struct ContentView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var lines: [RecognizedLine] = []
    @State private var translations: [UUID: String] = [:]
    @State private var targetLanguage = "en"
    @State private var configuration: TranslationSession.Configuration?
    @State private var status = "Take a screenshot and run the Translate Screenshot shortcut."
    @State private var autoTranslateAfterOCR = false
    @State private var translatedImage: UIImage?
    @State private var quickLookURL: URL?
    @State private var prepareSourceLanguage = "zh-Hans"
    @State private var preparingLanguages = false
    @State private var languagePackStatus = "Checking language pair…"

    private let languages = [
        ("da", "Danish"), ("en", "English"), ("de", "German"),
        ("fr", "French"), ("es", "Spanish"), ("sv", "Swedish"),
        ("no", "Norwegian"), ("it", "Italian"), ("pt", "Portuguese")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose image", systemImage: "photo")
                    }
                    .buttonStyle(.borderedProminent)

                    Picker("Translate to", selection: $targetLanguage) {
                        ForEach(languages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Picker("Source language", selection: $prepareSourceLanguage) {
                        Text("Japanese").tag("ja")
                        Text("Chinese (Simplified)").tag("zh-Hans")
                        Text("Korean").tag("ko")
                        Text("Danish").tag("da")
                        Text("German").tag("de")
                        Text("French").tag("fr")
                        Text("Spanish").tag("es")
                    }
                    .pickerStyle(.menu)
                    Button {
                        preparingLanguages = true
                        status = "Preparing Apple translation languages…"
                        let pair = TranslationSession.Configuration(
                            source: Locale.Language(identifier: prepareSourceLanguage),
                            target: Locale.Language(identifier: targetLanguage)
                        )
                        configuration = pair
                        configuration?.invalidate()
                    } label: {
                        Label("Download pack", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                }
                Text(languagePackStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let translatedImage {
                    Image(uiImage: translatedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: .infinity)
                    ShareLink(item: Image(uiImage: translatedImage), preview: SharePreview("QuickTranslate image")) {
                        Label("Share translated image", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                } else if let image {
                    GeometryReader { proxy in
                        let size = fittedSize(image.size, in: proxy.size)
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: proxy.size.width, height: proxy.size.height)

                            ForEach(lines) { line in
                                let rect = CGRect(
                                    x: line.box.minX * size.width + (proxy.size.width - size.width) / 2,
                                    y: (1 - line.box.maxY) * size.height + (proxy.size.height - size.height) / 2,
                                    width: line.box.width * size.width,
                                    height: line.box.height * size.height
                                )
                                Text(translations[line.id] ?? line.text)
                                    .font(.system(size: max(8, rect.height * 0.52), weight: .medium))
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.35)
                                    .multilineTextAlignment(.leading)
                                    .padding(1)
                                    .frame(width: max(1, rect.width), height: max(1, rect.height), alignment: .leading)
                                    .background(.white.opacity(0.96))
                                    .foregroundStyle(.black)
                                    .clipped()
                                    .position(x: rect.midX, y: rect.midY)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "No image selected",
                        systemImage: "text.viewfinder",
                        description: Text("Run the Translate Screenshot shortcut or choose an image.")
                    )
                    .frame(maxHeight: .infinity)
                }

                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    if lines.isEmpty {
                        guard let image else { return }
                        autoTranslateAfterOCR = true
                        status = "Reading text and preparing translation…"
                        recognizeText(in: image)
                    } else {
                        translations.removeAll()
                        translatedImage = nil
                        configuration = detectedTranslationConfiguration()
                        configuration?.invalidate()
                    }
                } label: {
                    Label(
                        lines.isEmpty ? "Scan & Translate" : "Translate detected text",
                        systemImage: "text.viewfinder"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(image == nil || autoTranslateAfterOCR)
            }
            .padding()
            .navigationTitle("QuickTranslate")
            .onAppear { processPendingScreenshot() }
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadPhoto(item) }
            }
            .translationTask(configuration) { session in
                if preparingLanguages {
                    do {
                        try await session.prepareTranslation()
                        await refreshLanguageAvailability()
                        status = languagePackStatus
                    } catch {
                        status = "Could not prepare languages: \(error.localizedDescription)"
                    }
                    preparingLanguages = false
                    return
                }
                do {
                    translations.removeAll()
                    var failedLines = 0
                    for line in lines {
                        do {
                            let result = try await session.translate(line.text)
                            translations[line.id] = result.targetText
                        } catch {
                            translations[line.id] = line.text
                            failedLines += 1
                        }
                    }
                    if let output = renderTranslatedImage() {
                        translatedImage = output
                        presentQuickLook(for: output)
                        status = failedLines == 0
                            ? "Translation complete."
                            : "Preview ready. \(failedLines) of \(lines.count) text lines could not be translated."
                    } else {
                        status = "Could not create the translated image."
                    }
                    autoTranslateAfterOCR = false
                } catch {
                    status = "Translation failed: \(error.localizedDescription)"
                    autoTranslateAfterOCR = false
                }
            }
        }
        .quickLookPreview($quickLookURL)
        .task(id: "\(prepareSourceLanguage)-\(targetLanguage)") {
            await refreshLanguageAvailability()
        }
    }

    @MainActor
    private func processPendingScreenshot() {
        guard let data = PendingScreenshotStore.take(),
              let uiImage = UIImage(data: data) else { return }
        image = uiImage
        lines = []
        translations = [:]
        translatedImage = nil
        autoTranslateAfterOCR = true
        status = "Reading screenshot and translating…"
        recognizeText(in: uiImage)
    }

    private func fittedSize(_ imageSize: CGSize, in bounds: CGSize) -> CGSize {
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            status = "Could not load that image."
            return
        }
        image = uiImage
        lines = []
        translations = [:]
        translatedImage = nil
        autoTranslateAfterOCR = true
        status = "Reading text and translating…"
        recognizeText(in: uiImage)
    }

    private func cgImageOrientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private func recognizeText(in image: UIImage) {
        guard let cgImage = image.cgImage else {
            status = "This image could not be processed."
            autoTranslateAfterOCR = false
            return
        }
        let request = VNRecognizeTextRequest { request, error in
            DispatchQueue.main.async {
                if let error {
                    status = "Text recognition failed: \(error.localizedDescription)"
                    autoTranslateAfterOCR = false
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let candidates = observations.compactMap { $0.topCandidates(1).first }
                let confidenceValues = candidates.map(\.confidence).sorted()
                let medianConfidence = confidenceValues.isEmpty ? 0 : confidenceValues[confidenceValues.count / 2]
                let confidenceFloor = max(Float(0.10), medianConfidence * 0.30)
                let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                let detected = observations.compactMap { observation -> RecognizedLine? in
                    guard let candidate = observation.topCandidates(1).first,
                          candidate.confidence >= confidenceFloor,
                          observation.boundingBox.height >= 0.006,
                          observation.boundingBox.midY > 0.025,
                          observation.boundingBox.midY < 0.985 else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    let usefulCharacters = text.unicodeScalars.filter {
                        CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
                    }.count
                    guard usefulCharacters >= 2 else { return nil }
                    let normalized = observation.boundingBox
                    let pixelRect = CGRect(
                        x: normalized.minX * imageSize.width,
                        y: (1 - normalized.maxY) * imageSize.height,
                        width: normalized.width * imageSize.width,
                        height: normalized.height * imageSize.height
                    ).integral
                    guard pixelRect.width > 5, pixelRect.height > 4 else { return nil }
                    var glyphRects: [CGRect] = []
                    var cursor = candidate.string.startIndex
                    while cursor < candidate.string.endIndex {
                        let next = candidate.string.index(after: cursor)
                        if let glyphObservation = (try? candidate.boundingBox(for: cursor..<next)).flatMap({ $0 }) {
                            let glyph = glyphObservation.boundingBox
                            let glyphRect = CGRect(
                                x: glyph.minX * imageSize.width,
                                y: (1 - glyph.maxY) * imageSize.height,
                                width: glyph.width * imageSize.width,
                                height: glyph.height * imageSize.height
                            )
                            if glyphRect.width > 0, glyphRect.height > 0,
                               glyphRect.origin.x.isFinite, glyphRect.origin.y.isFinite {
                                glyphRects.append(glyphRect)
                            }
                        }
                        cursor = next
                    }
                    return RecognizedLine(text: text, box: normalized,
                        confidence: candidate.confidence, pixelRect: pixelRect, glyphRects: glyphRects)
                }
                let ranked = detected.sorted {
                    if $0.text.count != $1.text.count { return $0.text.count > $1.text.count }
                    return $0.confidence > $1.confidence
                }
                var unique: [RecognizedLine] = []
                for line in ranked {
                    let duplicate = unique.contains { other in
                        let overlap = line.pixelRect.intersection(other.pixelRect)
                        guard !overlap.isNull else { return false }
                        let area = overlap.width * overlap.height
                        let smaller = min(line.pixelRect.width * line.pixelRect.height,
                                          other.pixelRect.width * other.pixelRect.height)
                        return smaller > 0 && area / smaller > 0.85
                            && line.text.localizedCaseInsensitiveCompare(other.text) == .orderedSame
                    }
                    if !duplicate { unique.append(line) }
                }
                lines = unique.sorted {
                    if abs($0.pixelRect.midY - $1.pixelRect.midY) > max($0.pixelRect.height, $1.pixelRect.height) * 0.45 {
                        return $0.pixelRect.minY < $1.pixelRect.minY
                    }
                    return $0.pixelRect.minX < $1.pixelRect.minX
                }
                status = "Found \(lines.count) text regions."
                if lines.isEmpty {
                    autoTranslateAfterOCR = false
                    status = "No readable text was found. Try cropping away the app interface."
                } else if autoTranslateAfterOCR {
                    configuration = detectedTranslationConfiguration()
                    configuration?.invalidate()
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.007
        let orientation = cgImageOrientation(for: image.imageOrientation)
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    status = "Text recognition failed: \(error.localizedDescription)"
                    autoTranslateAfterOCR = false
                }
            }
        }
    }

    @MainActor
    private func refreshLanguageAvailability() async {
        let availability = LanguageAvailability()
        let source = Locale.Language(identifier: prepareSourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        let result = await availability.status(from: source, to: target)
        switch result {
        case .installed:
            languagePackStatus = "Downloaded and ready: \(prepareSourceLanguage) → \(targetLanguage)"
        case .supported:
            languagePackStatus = "Available to download: \(prepareSourceLanguage) → \(targetLanguage)"
        case .unsupported:
            languagePackStatus = "Apple doesn't support this language pair."
        @unknown default:
            languagePackStatus = "Couldn't determine language-pack availability."
        }
    }

    private func detectedTranslationConfiguration() -> TranslationSession.Configuration {
        // Let Apple Translation detect the source for each OCR fragment. A
        // single guessed language is unreliable on mixed-language manga pages.
        TranslationSession.Configuration(
            source: Locale.Language(identifier: prepareSourceLanguage),
            target: Locale.Language(identifier: targetLanguage)
        )
    }

    private func presentQuickLook(for image: UIImage) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickTranslate-\(UUID().uuidString).png")
        guard let data = image.pngData() else {
            status = "Could not prepare the Quick Look preview."
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            quickLookURL = url
        } catch {
            status = "Could not open the translated image preview: \(error.localizedDescription)"
        }
    }

    private func renderTranslatedImage() -> UIImage? {
        guard let image, let source = image.cgImage,
              lines.allSatisfy({ translations[$0.id] != nil }) else { return nil }
        let boxes = lines.map {
            RecognizedTextBox(text: $0.text, confidence: $0.confidence,
                              rect: $0.pixelRect, glyphRects: $0.glyphRects)
        }
        let translated = lines.map { translations[$0.id] ?? $0.text }
        guard let rendered = try? ScreenshotRenderer().render(
            source: source, boxes: boxes, translations: translated
        ) else { return nil }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: image.imageOrientation)
    }
}
