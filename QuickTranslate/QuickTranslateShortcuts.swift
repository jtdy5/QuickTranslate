import AppIntents
import Vision
import UIKit
import UniformTypeIdentifiers
import Translation
import NaturalLanguage

private func recognizedObservations(in data: Data) throws -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true
    request.minimumTextHeight = 0.007

    let handler = VNImageRequestHandler(data: data)
    try handler.perform([request])

    let filtered = (request.results ?? []).filter { observation in
        guard observation.confidence >= 0.35 else { return false }
        let box = observation.boundingBox
        guard box.height >= 0.007, box.midY > 0.055, box.midY < 0.96 else { return false }
        guard let candidate = observation.topCandidates(1).first else { return false }
        let letterCount = candidate.string.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }.count
        return letterCount >= 2
    }

    return filtered.sorted {
        if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012 {
            return $0.boundingBox.midY > $1.boundingBox.midY
        }
        return $0.boundingBox.minX < $1.boundingBox.minX
    }
}

private func makeTranslatedImage(
    original: UIImage,
    observations: [VNRecognizedTextObservation],
    translations: [String]
) throws -> IntentFile {
    guard observations.count == translations.count else {
        throw NSError(domain: "QuickTranslate", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "The number of translated lines did not match the detected text. Please try the screenshot again."])
    }

    let renderer = UIGraphicsImageRenderer(size: original.size)
    let rendered = renderer.image { _ in
        original.draw(in: CGRect(origin: .zero, size: original.size))

        for (observation, translation) in zip(observations, translations) {
            let box = observation.boundingBox
            let rect = CGRect(
                x: box.minX * original.size.width,
                y: (1 - box.maxY) * original.size.height,
                width: box.width * original.size.width,
                height: box.height * original.size.height
            ).insetBy(dx: -3, dy: -2)

            let safeRect = rect.intersection(CGRect(origin: .zero, size: original.size))
            guard !safeRect.isNull, !safeRect.isEmpty else { continue }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping

            let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            let available = safeRect.insetBy(dx: 2, dy: 1)
            let baseFontSize = max(7, safeRect.height * 0.72)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: baseFontSize, weight: .medium),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]

            for size in stride(from: baseFontSize, through: 6, by: -1) {
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

    guard let png = rendered.pngData() else {
        throw NSError(domain: "QuickTranslate", code: 5,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create the translated image."])
    }

    return IntentFile(data: png, filename: "QuickTranslate-Translated.png", type: .png)
}

/// Performs OCR, language detection, translation, and image rendering in one Shortcut action.
struct TranslateScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription(
        "Automatically detects and translates text in a screenshot, then returns the finished translated image."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Screenshot",
        description: "The screenshot to translate.",
        supportedContentTypes: [.image]
    )
    var screenshot: IntentFile

    @Parameter(title: "Translate to", default: "en")
    var targetLanguage: String

    func perform() async throws -> some ReturnsValue<IntentFile> {
        let data = screenshot.data
        let observations = try recognizedObservations(in: data)

        guard !observations.isEmpty else {
            throw NSError(domain: "QuickTranslate", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No readable text was found. Try a clearer screenshot or crop away the app interface."])
        }

        let sourceLines = observations.compactMap { $0.topCandidates(1).first?.string }
        guard sourceLines.count == observations.count else {
            throw NSError(domain: "QuickTranslate", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Some detected text could not be read."])
        }

        let languageSample = sourceLines.joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(languageSample)
        guard let detectedLanguage = recognizer.dominantLanguage else {
            throw NSError(domain: "QuickTranslate", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "QuickTranslate could not identify the language. Try a screenshot containing more readable dialogue."])
        }

        guard let original = UIImage(data: data) else {
            throw NSError(domain: "QuickTranslate", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "The supplied screenshot could not be opened as an image."])
        }

        guard #available(iOS 26.0, *) else {
            throw NSError(domain: "QuickTranslate", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "Automatic Shortcut translation requires iOS 26 or later. You can still translate images from inside the QuickTranslate app."])
        }

        let source = Locale.Language(identifier: detectedLanguage.rawValue)
        let target = Locale.Language(identifier: targetLanguage)
        let session = TranslationSession(installedSource: source, target: target)

        var translatedLines: [String] = []
        translatedLines.reserveCapacity(sourceLines.count)
        for line in sourceLines {
            let response = try await session.translate(line)
            translatedLines.append(response.targetText)
        }

        let file = try makeTranslatedImage(
            original: original,
            observations: observations,
            translations: translatedLines
        )
        return .result(value: file)
    }
}

struct OpenQuickTranslateIntent: AppIntent {
    static var title: LocalizedStringResource = "Open QuickTranslate"
    static var description = IntentDescription("Opens QuickTranslate.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct QuickTranslateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateScreenshotIntent(),
            phrases: ["Translate my latest screenshot with \(.applicationName)"],
            shortTitle: "Translate Screenshot",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: OpenQuickTranslateIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open QuickTranslate",
            systemImageName: "translate"
        )
    }
}
