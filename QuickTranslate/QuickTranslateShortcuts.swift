import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Hands the screenshot to the app so its interactive preview can be used.
/// Quick Look is deliberately not returned: it is a static preview and cannot
/// expose the Original / Translation controls.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription("Send the screenshot to QuickTranslate for automatic OCR and translation in the interactive app preview.")
    static var openAppWhenRun = true

    @Parameter(title: "Screenshot", description: "Select the Screenshot magic variable from the preceding Take Screenshot action.")
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$screenshot) to English")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        try PendingScreenshotStore.save(screenshot.data)
        // Keep the same output type as the previous Shortcut action so its
        // downstream magic-variable connection remains available.
        return .result(value: screenshot)
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
