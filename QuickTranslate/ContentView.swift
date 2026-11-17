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
    @State private var targetLanguage = "da"
    @State private var configuration: TranslationSession.Configuration?
    @State private var status = "Choose a screenshot or photo to begin."

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

                if let image {
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
                    configuration = TranslationSession.Configuration(
                        source: nil,
                        target: Locale.Language(identifier: targetLanguage)
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(lines.isEmpty)
            }
            .padding()
            .navigationTitle("QuickTranslate")
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadPhoto(item) }
            }
            .translationTask(configuration) { session in
                do {
                    for line in lines {
                        let result = try await session.translate(line.text)
                        translations[line.id] = result.targetText
                    }
                    status = "Translation complete."
                } catch {
                    status = "Translation failed: \(error.localizedDescription)"
                }
            }
        }
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
            return
        }
        let request = VNRecognizeTextRequest { request, error in
            DispatchQueue.main.async {
                if let error {
                    status = "Text recognition failed: \(error.localizedDescription)"
                    return
                }
                lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { observation in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    return RecognizedLine(text: text, box: observation.boundingBox)
                }
                status = "Found \(lines.count) text lines."
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImageOrientation(for: image.imageOrientation))
            try? handler.perform([request])
        }
    }
}
