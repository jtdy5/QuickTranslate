import Foundation
import UIKit
import Vision
import NaturalLanguage
import Translation
import ImageIO

enum ImageTranslationProcessor {
    enum ProcessingError: LocalizedError {
        case unreadableImage
        case noText
        case noLanguage
        case translationUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "QuickTranslate couldn't read the screenshot."
            case .noText: return "No readable text was found in the screenshot."
            case .noLanguage: return "The source language couldn't be identified."
            case .translationUnavailable(let language):
                return "The on-device translation language for \(language) isn't installed. Download that language pair in Settings > Apps > Translate, then try again."
            }
        }
    }

    private struct OCRLine {
        let text: String
        let rect: CGRect
        let confidence: Float
        let glyphRects: [CGRect]
    }

    static func translate(_ data: Data, targetLanguage: String) async throws -> Data {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw ProcessingError.unreadableImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.006
        try VNImageRequestHandler(cgImage: cgImage, orientation: orientation(image.imageOrientation)).perform([request])

        let observations = request.results ?? []
        let raw = observations.compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let useful = text.unicodeScalars.filter {
                CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
            }.count
            guard useful >= 2, candidate.confidence >= 0.12,
                  observation.boundingBox.height >= 0.005 else { return nil }

            let b = observation.boundingBox
            let rect = CGRect(
                x: b.minX * CGFloat(cgImage.width),
                y: (1 - b.maxY) * CGFloat(cgImage.height),
                width: b.width * CGFloat(cgImage.width),
                height: b.height * CGFloat(cgImage.height)
            ).integral
            guard rect.width > 4, rect.height > 3 else { return nil }

            var glyphs: [CGRect] = []
            var cursor = candidate.string.startIndex
            while cursor < candidate.string.endIndex {
                let next = candidate.string.index(after: cursor)
                if let glyph = (try? candidate.boundingBox(for: cursor..<next)) ?? nil {
                    let r = glyph.boundingBox
                    glyphs.append(CGRect(
                        x: r.minX * CGFloat(cgImage.width),
                        y: (1 - r.maxY) * CGFloat(cgImage.height),
                        width: r.width * CGFloat(cgImage.width),
                        height: r.height * CGFloat(cgImage.height)
                    ))
                }
                cursor = next
            }
            return OCRLine(text: text, rect: rect, confidence: candidate.confidence, glyphRects: glyphs)
        }

        let sorted = raw.sorted {
            if abs($0.rect.midY - $1.rect.midY) > max($0.rect.height, $1.rect.height) * 0.45 {
                return $0.rect.minY < $1.rect.minY
            }
            return $0.rect.minX < $1.rect.minX
        }
        var lines: [OCRLine] = []
        for line in sorted {
            let duplicate = lines.contains { other in
                let overlap = line.rect.intersection(other.rect)
                guard !overlap.isNull else { return false }
                let smaller = min(line.rect.width * line.rect.height, other.rect.width * other.rect.height)
                return smaller > 0 && overlap.width * overlap.height / smaller > 0.85
                    && line.text.localizedCaseInsensitiveCompare(other.text) == .orderedSame
            }
            if !duplicate { lines.append(line) }
        }
        guard !lines.isEmpty else { throw ProcessingError.noText }

        let allText = lines.map(\.text).joined(separator: " ")
        let wholeRecognizer = NLLanguageRecognizer()
        wholeRecognizer.processString(allText)
        guard let dominant = wholeRecognizer.dominantLanguage?.rawValue else {
            throw ProcessingError.noLanguage
        }

        var sessions: [String: TranslationSession] = [:]
        var translations: [String] = []
        var skipped = Set<Int>()

        for (index, line) in lines.enumerated() {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(line.text)
            let detected = recognizer.dominantLanguage?.rawValue
            let sourceCode = (line.text.count >= 4 ? detected : nil) ?? dominant

            if sourceCode == targetLanguage || sourceCode.hasPrefix(targetLanguage + "-") {
                translations.append(line.text)
                skipped.insert(index)
                continue
            }

            do {
                let session: TranslationSession
                if let existing = sessions[sourceCode] {
                    session = existing
                } else {
                    do {
                        session = try TranslationSession(
                            installedSource: Locale.Language(identifier: sourceCode),
                            target: Locale.Language(identifier: targetLanguage)
                        )
                    } catch {
                        throw ProcessingError.translationUnavailable(sourceCode)
                    }
                    sessions[sourceCode] = session
                }
                let result = try await session.translate(line.text)
                let translated = result.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if translated.isEmpty || translated == line.text {
                    translations.append(line.text)
                    skipped.insert(index)
                } else {
                    translations.append(translated)
                }
            } catch let error as ProcessingError {
                throw error
            } catch {
                translations.append(line.text)
                skipped.insert(index)
            }
        }

        let boxes = lines.map {
            RecognizedTextBox(text: $0.text, confidence: $0.confidence, rect: $0.rect, glyphRects: $0.glyphRects)
        }
        let rendered = try ScreenshotRenderer().render(
            source: cgImage,
            boxes: boxes,
            translations: translations,
            skippedIndices: skipped
        )
        let output = UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
        guard let png = output.pngData() else { throw ProcessingError.unreadableImage }
        return png
    }

    private static func orientation(_ value: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch value {
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        default: return .up
        }
    }
}
