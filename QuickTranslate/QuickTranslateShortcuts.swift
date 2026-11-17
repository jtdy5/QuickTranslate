import AppIntents
import Vision

/// Recognizes text from the screenshot supplied by the preceding Shortcuts action.
struct ExtractTextFromScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Latest Screenshot"
    static var description = IntentDescription(
        "Recognizes text in the screenshot passed from the previous Shortcuts action, making it available to Translate and Quick Look."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Screenshot",
        description: "Connect this to the image output of the Take Screenshot or Find Photos action.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    func perform() async throws -> some ReturnsValue<String> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(data: screenshot.data)
        try handler.perform([request])

        let observations = request.results ?? []
        let recognizedText = observations
            .sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\\n")

        guard !recognizedText.isEmpty else {
            throw NSError(
                domain: "QuickTranslate",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No readable text was found in the supplied screenshot."]
            )
        }

        return .result(value: recognizedText)
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
