import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Receives the image output from the preceding Take Screenshot action,
/// translates it on-device, and returns the translated PNG for Quick Look.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription("Translate the screenshot supplied by the previous Shortcut action to English offline and return the translated image.")
    static var openAppWhenRun = false

    // Keep this required and include it in parameterSummary. That makes the
    // screenshot input visible in the Shortcuts editor so the Take Screenshot
    // magic variable can be connected instead of silently running with nil.
    @Parameter(title: "Screenshot", description: "Select the Screenshot magic variable from the preceding Take Screenshot action.")
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \\(.\\$screenshot) to English")
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
