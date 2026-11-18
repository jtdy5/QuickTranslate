import AppIntents
import Vision
import UIKit
import UniformTypeIdentifiers

private let quickTranslateSeparator = " ⟦QTSEG⟧ "

private func recognizedObservations(in data: Data) throws -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.minimumTextHeight = 0.004

    let handler = VNImageRequestHandler(data: data)
    try handler.perform([request])

    return (request.results ?? []).sorted {
        if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012 {
            return $0.boundingBox.midY > $1.boundingBox.midY
        }
        return $0.boundingBox.minX < $1.boundingBox.minX
    }
}

/// Extracts individual OCR regions, separated by a marker so Shortcuts can translate them together.
struct ExtractTextFromScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Latest Screenshot"
    static var description = IntentDescription(
        "Recognizes text regions in a screenshot so Shortcuts can translate them."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Screenshot",
        description: "The screenshot to recognize.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    func perform() async throws -> some ReturnsValue<String> {
        let observations = try recognizedObservations(in: screenshot.data)
        let blocks = observations.compactMap { $0.topCandidates(1).first?.string }
            .map { $0.replacingOccurrences(of: "\n", with: " ") }

        guard !blocks.isEmpty else {
            throw NSError(domain: "QuickTranslate", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No readable text was found in the supplied screenshot."])
        }

        return .result(value: blocks.joined(separator: quickTranslateSeparator))
    }
}

/// Re-runs the same OCR and places each translated block over its original region.
struct RenderTranslatedScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Translated Screenshot"
    static var description = IntentDescription(
        "Places translated text over the detected text regions and returns a translated image for Quick Look."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Original Screenshot",
        description: "Connect the screenshot from Find Photos using the Shortcut variable picker; do not choose a file when running.",
        supportedContentTypes: [.image]
    )
    var screenshot: IntentFile

    @Parameter(
        title: "Translated Text",
        description: "Connect this to the output of the Translate Text action.",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var translatedText: String

    func perform() async throws -> some ReturnsValue<IntentFile> {
        let observations = try recognizedObservations(in: screenshot.data)
        let translatedBlocks = translatedText.components(separatedBy: quickTranslateSeparator)

        guard !observations.isEmpty else {
            throw NSError(domain: "QuickTranslate", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No text regions could be found in the original screenshot."])
        }

        guard translatedBlocks.count == observations.count else {
            throw NSError(domain: "QuickTranslate", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The translation changed the text separators. Try translating without changing the ⟦QTSEG⟧ markers."])
        }

        guard let original = UIImage(data: screenshot.data) else {
            throw NSError(domain: "QuickTranslate", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "The supplied screenshot could not be opened as an image."])
        }

        let renderer = UIGraphicsImageRenderer(size: original.size)
        let rendered = renderer.image { context in
            original.draw(in: CGRect(origin: .zero, size: original.size))

            for (observation, translation) in zip(observations, translatedBlocks) {
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

                let baseFontSize = max(7, safeRect.height * 0.72)
                var chosenFont = UIFont.systemFont(ofSize: baseFontSize, weight: .medium)
                let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: chosenFont,
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph
                ]

                let available = safeRect.insetBy(dx: 2, dy: 1)
                for size in stride(from: baseFontSize, through: 6, by: -1) {
                    chosenFont = UIFont.systemFont(ofSize: size, weight: .medium)
                    attributes[.font] = chosenFont
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
                (text as NSString).draw(
                    in: available,
                    withAttributes: attributes
                )
            }
        }

        guard let png = rendered.pngData() else {
            throw NSError(domain: "QuickTranslate", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create the translated image."])
        }

        return .result(value: IntentFile(data: png, filename: "QuickTranslate-Translated.png", type: .png))
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
            intent: ExtractTextFromScreenshotIntent(),
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
