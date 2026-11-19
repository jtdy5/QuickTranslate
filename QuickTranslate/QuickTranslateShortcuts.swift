import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Runs OCR and on-device translation in the Shortcut process, then returns
/// the finished PNG directly to the next Shortcut action (for example Quick Look).
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription("Translates a screenshot and returns the finished image without opening QuickTranslate.")
    static var openAppWhenRun = false

    @Parameter(
        title: "Screenshot",
        description: "Connect this to the Take Screenshot action directly above it.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \\.$screenshot")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let pngData = try await ImageTranslationProcessor.translate(
            screenshot.data,
            targetLanguage: "en"
        )
        let output = IntentFile(data: pngData, filename: "QuickTranslate-Translated.png", type: .png)
        return .result(value: output, dialog: "Translation complete. The translated image is ready.")
    }
}

struct OpenQuickTranslateIntent: AppIntent {
    static var title: LocalizedStringResource = "Open QuickTranslate"
    static var description = IntentDescription("Opens QuickTranslate.")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}

struct QuickTranslateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateLatestScreenshotIntent(),
            phrases: ["Translate my screenshot with \\(.applicationName)", "Translate screen with \\(.applicationName)"],
            shortTitle: "Translate Screenshot",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: OpenQuickTranslateIntent(),
            phrases: ["Open \\(.applicationName)"],
            shortTitle: "Open QuickTranslate",
            systemImageName: "translate"
        )
    }
}
