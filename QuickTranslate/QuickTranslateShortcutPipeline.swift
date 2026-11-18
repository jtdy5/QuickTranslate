import AppIntents
import Foundation
import UIKit
import UniformTypeIdentifiers
import Vision
import Translation
import NaturalLanguage

/// Performs the entire screenshot-to-image workflow inside the App Intent.
/// Returning an IntentFile lets Shortcuts pass the translated PNG to Quick Look
/// without launching the containing app.
enum QuickTranslateShortcutPipeline {
    enum PipelineError: LocalizedError {
        case invalidImage
        case noText
        case languageNotDetected
        case noTranslation

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "The screenshot could not be opened as an image."
            case .noText: return "No readable text was found in the screenshot."
            case .languageNotDetected: return "The source language could not be detected. Try a clearer screenshot."
            case .noTranslation: return "The translation service returned no translated text."
            }
        }
    }

    static func translate(_ data: Data) async throws -> IntentFile {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw PipelineError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.007

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImagePropertyOrientation)
        try handler.perform([request])

        let observations = request.results ?? []
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let boxes: [RecognizedTextBox] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let usefulCharacters = text.unicodeScalars.filter {
                CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
            }.count
            guard usefulCharacters >= 2,
                  observation.boundingBox.height >= 0.006,
                  observation.boundingBox.midY > 0.025,
                  observation.boundingBox.midY < 0.985 else { return nil }

            let normalized = observation.boundingBox
            let rect = CGRect(
                x: normalized.minX * imageSize.width,
                y: (1 - normalized.maxY) * imageSize.height,
                width: normalized.width * imageSize.width,
                height: normalized.height * imageSize.height
            ).integral
            guard rect.width > 5, rect.height > 4 else { return nil }

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
                    if glyphRect.width > 0, glyphRect.height > 0 {
                        glyphRects.append(glyphRect)
                    }
                }
                cursor = next
            }
            return RecognizedTextBox(
                text: text,
                confidence: candidate.confidence,
                rect: rect,
                glyphRects: glyphRects
            )
        }

        guard !boxes.isEmpty else { throw PipelineError.noText }

        // Deduplicate overlapping OCR results while retaining the strongest
        // and longest recognition, matching the in-app OCR behaviour.
        let ranked = boxes.sorted {
            if $0.text.count != $1.text.count { return $0.text.count > $1.text.count }
            return $0.confidence > $1.confidence
        }
        var unique: [RecognizedTextBox] = []
        for box in ranked {
            let duplicate = unique.contains { other in
                let overlap = box.rect.intersection(other.rect)
                guard !overlap.isNull else { return false }
                let overlapArea = overlap.width * overlap.height
                let smallerArea = min(box.rect.width * box.rect.height,
                                      other.rect.width * other.rect.height)
                return smallerArea > 0 && overlapArea / smallerArea > 0.85
                    && box.text.localizedCaseInsensitiveCompare(other.text) == .orderedSame
            }
            if !duplicate { unique.append(box) }
        }
        let ordered = unique.sorted {
            if abs($0.rect.midY - $1.rect.midY) > max($0.rect.height, $1.rect.height) * 0.45 {
                return $0.rect.minY < $1.rect.minY
            }
            return $0.rect.minX < $1.rect.minX
        }

        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(ordered.map(\.text).joined(separator: "\n"))
        guard let sourceLanguage = languageRecognizer.dominantLanguage,
              sourceLanguage != .und else {
            throw PipelineError.languageNotDetected
        }

        // This initializer is designed for non-UI contexts such as App Intents.
        // It uses already-installed on-device language models and never opens
        // the app just to display a translation screen.
        let session = try TranslationSession(
            installedSource: Locale.Language(identifier: sourceLanguage.rawValue),
            target: Locale.Language(identifier: "en")
        )
        let requests = ordered.map { TranslationSession.Request(sourceText: $0.text) }
        let responses = try await session.translations(from: requests)
        let translated = responses.map(\.targetText)
        guard translated.count == ordered.count else { throw PipelineError.noTranslation }

        let rendered = try ScreenshotRenderer().render(
            source: cgImage,
            boxes: ordered,
            translations: translated
        )
        let outputImage = UIImage(cgImage: rendered)
        guard let pngData = outputImage.pngData() else { throw PipelineError.invalidImage }

        return IntentFile(data: pngData, filename: "QuickTranslate-Translated.png", type: .png)
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
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
}
