import SwiftUI
import UIKit
import PhotosUI
import Vision
import Translation
import ImageIO

struct RecognizedLine: Identifiable {
    let id = UUID()
    let text: String
    let box: CGRect
}

struct ContentView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var lines: [RecognizedLine] = []
    @State private var translations: [UUID: String] = [:]
    @State private var targetLanguage = "en"
    @State private var configuration: TranslationSession.Configuration?
    @State private var status = "Choose a screenshot or photo to begin."
    @State private var autoTranslateAfterOCR = false
    @State private var translatedImage: UIImage?

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
                    ContentUnavailableView("No image selected", systemImage: "text.viewfinder",
                                           description: Text("Choose a screenshot or photo containing text."))
                    .frame(maxHeight: .infinity)
                }

                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Translate detected text") {
                    translations.removeAll()
                    translatedImage = nil
                    configuration = TranslationSession.Configuration(
                        source: nil,
                        target: Locale.Language(identifier: targetLanguage)
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(lines.isEmpty || autoTranslateAfterOCR)
            }
            .padding()
            .navigationTitle("QuickTranslate")
            .onAppear {
                processPendingShortcutScreenshot()
            }
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadPhoto(item) }
            }
            .translationTask(configuration) { session in
                do {
                    translations.removeAll()
                    for line in lines {
                        let result = try await session.translate(line.text)
                        translations[line.id] = result.targetText
                    }
                    translatedImage = renderTranslatedImage()
                    status = "Translation complete."
                    autoTranslateAfterOCR = false
                } catch {
                    status = "Translation failed: \\(error.localizedDescription)"
                    autoTranslateAfterOCR = false
                }
            }
        }
    }

    private func fittedSize(_ imageSize: CGSize, in bounds: CGSize) -> CGSize {
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func processPendingShortcutScreenshot() {
        let directory = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        guard let directory else { return }
        let screenshotURL = directory.appendingPathComponent("QuickTranslate-pending-screenshot")
        let languageURL = directory.appendingPathComponent("QuickTranslate-target-language")
        guard let data = try? Data(contentsOf: screenshotURL),
              let uiImage = UIImage(data: data) else { return }

        try? FileManager.default.removeItem(at: screenshotURL)
        if let language = try? String(contentsOf: languageURL, encoding: .utf8),
           languages.contains(where: { $0.0 == language }) {
            targetLanguage = language
        }
        try? FileManager.default.removeItem(at: languageURL)

        selectedPhoto = nil
        image = uiImage
        lines = []
        translations = [:]
        translatedImage = nil
        autoTranslateAfterOCR = true
        status = "Reading screenshot and detecting language…"
        recognizeText(in: uiImage)
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
        autoTranslateAfterOCR = false
        status = "Reading text…"
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
                    status = "Text recognition failed: \\(error.localizedDescription)"
                    autoTranslateAfterOCR = false
                    return
                }
                lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { observation in
                    guard observation.confidence >= 0.35,
                          observation.boundingBox.height >= 0.007,
                          observation.boundingBox.midY > 0.055,
                          observation.boundingBox.midY < 0.96,
                          let text = observation.topCandidates(1).first?.string,
                          text.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 2
                    else { return nil }
                    return RecognizedLine(text: text, box: observation.boundingBox)
                }
                status = "Found \\(lines.count) text lines."
                if lines.isEmpty {
                    autoTranslateAfterOCR = false
                    status = "No readable text was found. Try cropping away the app interface."
                } else if autoTranslateAfterOCR {
                    configuration = TranslationSession.Configuration(
                        source: nil,
                        target: Locale.Language(identifier: targetLanguage)
                    )
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.007
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImageOrientation(for: image.imageOrientation))
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    status = "Text recognition failed: \\(error.localizedDescription)"
                    autoTranslateAfterOCR = false
                }
            }
        }
    }

    private func renderTranslatedImage() -> UIImage? {
        guard let image, lines.allSatisfy({ translations[$0.id] != nil }) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            for line in lines {
                guard let translated = translations[line.id] else { continue }
                let box = line.box
                let rect = CGRect(
                    x: box.minX * image.size.width,
                    y: (1 - box.maxY) * image.size.height,
                    width: box.width * image.size.width,
                    height: box.height * image.size.height
                ).insetBy(dx: -3, dy: -2)
                let safeRect = rect.intersection(CGRect(origin: .zero, size: image.size))
                guard !safeRect.isNull, !safeRect.isEmpty else { continue }

                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byWordWrapping
                let text = translated.trimmingCharacters(in: .whitespacesAndNewlines)
                let available = safeRect.insetBy(dx: 2, dy: 1)
                let baseSize = max(7, safeRect.height * 0.72)
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: baseSize, weight: .medium),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph
                ]
                for size in stride(from: baseSize, through: 6, by: -1) {
                    attributes[.font] = UIFont.systemFont(ofSize: size, weight: .medium)
                    let measured = (text as NSString).boundingRect(
                        with: CGSize(width: max(1, available.width), height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes,
                        context: nil
                    )
                    if measured.height <= available.height { break }
                }
                UIColor.white.withAlphaComponent(0.97).setFill()
                UIBezierPath(roundedRect: safeRect, cornerRadius: 2).fill()
                (text as NSString).draw(in: available, withAttributes: attributes)
            }
        }
    }
}
