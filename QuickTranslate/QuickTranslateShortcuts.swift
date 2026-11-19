import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Accepts the screenshot produced by the previous Shortcuts action, translates
/// it on-device, and returns the translated PNG for Quick Look.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription("Translate the screenshot supplied by the previous Shortcut action to English offline and return the translated image.")
    static var openAppWhenRun = false

    @Parameter(title: "Screenshot", description: "The screenshot captured by the previous action.")
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \\.$screenshot to English")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let pngData = try await ImageTranslationProcessor.translate(
            screenshot.data,
            targetLanguage: "en"
        )
        let output = IntentFile(data: pngData, filename: "QuickTranslate-Translated.png", type: .png)
        return .result(value: output)
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
