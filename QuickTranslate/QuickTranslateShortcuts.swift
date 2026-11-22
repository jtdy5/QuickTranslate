import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Keeps the Shortcut's Screenshot input and translated-image output stable.
/// The original image is also handed to the app for its interactive preview.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription("Translate the supplied screenshot and open QuickTranslate's interactive preview.")
    static var openAppWhenRun = true

    @Parameter(title: "Screenshot", description: "Screenshot from the preceding Take Screenshot action.")
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$screenshot) to English")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        try PendingScreenshotStore.save(screenshot.data)
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
