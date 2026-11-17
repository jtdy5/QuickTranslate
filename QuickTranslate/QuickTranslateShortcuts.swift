import AppIntents
import Vision
import ImageIO

/// Extracts readable text from an image shared to the QuickTranslate shortcut.
/// The returned text can be passed to Apple's Translate Text and Quick Look actions.
struct ExtractTextFromScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Extract Text from Screenshot"
    static var description = IntentDescription(
        "Recognizes text in a shared screenshot or image so it can be translated and previewed."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Screenshot")
    var screenshot: IntentFile

    func perform() async throws -> some ReturnsValue<String> {
        let data = screenshot.data
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(data: data)
        try handler.perform([request])

        let observations = request.results ?? []
        let text = observations
            .sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        guard !text.isEmpty else {
            throw NSError(
                domain: "QuickTranslate",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No readable text was found in that image."]
            )
        }

        return .result(value: text)
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
            phrases: ["Extract text with \u{0024}{applicationName}"],
            shortTitle: "Translate Screenshot",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: OpenQuickTranslateIntent(),
            phrases: ["Open \u{0024}{applicationName}"],
            shortTitle: "Open QuickTranslate",
            systemImageName: "translate"
        )
    }
}
