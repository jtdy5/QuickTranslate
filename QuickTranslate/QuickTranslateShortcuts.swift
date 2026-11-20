import AppIntents
import Foundation
import UniformTypeIdentifiers

private enum ShortcutInputError: LocalizedError {
    case missingScreenshot

    var errorDescription: String? {
        switch self {
        case .missingScreenshot:
            return "No screenshot was passed to QuickTranslate. In Shortcuts, connect the image output from Take Screenshot to the Screenshot input."
        }
    }
}

/// Accepts the screenshot produced by the previous Shortcuts action, translates
/// it on-device, and returns the translated PNG for Quick Look.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription("Translate the screenshot supplied by the previous Shortcut action to English offline and return the translated image.")
    static var openAppWhenRun = false

    // Optional prevents Shortcuts from presenting a mandatory file-picker prompt
    // when the action is first added. The screenshot should be supplied by the
    // preceding Take Screenshot action's output.
    @Parameter(title: "Screenshot", description: "Connect the image output from Take Screenshot.")
    var screenshot: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("Translate screenshot to English")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let screenshot else {
            throw ShortcutInputError.missingScreenshot
        }
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
            phrases: ["Translate my screenshot with \(.applicationName)", "Translate screen with \(.applicationName)"],
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
