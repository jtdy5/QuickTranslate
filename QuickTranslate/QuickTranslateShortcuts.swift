import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Receives the image produced by Take Screenshot and returns the translated image to Quick Look.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription("Translate the screenshot supplied by the preceding Shortcut action.")
    static var openAppWhenRun = false

    @Parameter(
        title: "Screenshot",
        description: "Image produced by the preceding Take Screenshot action.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$screenshot) to English")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let translatedData = try await ImageTranslationProcessor.translate(
            screenshot.data,
            targetLanguage: "en"
        )
        let output = IntentFile(data: translatedData, filename: "QuickTranslate-Translated.png", type: .png)
        return .result(value: output)
    }
}

struct QuickTranslateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateLatestScreenshotIntent(),
            phrases: ["Translate my screenshot with \(.applicationName)", "Translate screen with \(.applicationName)"],
            shortTitle: "Translate Screenshot",
            systemImageName: "text.viewfinder"
        )
    }
}
