import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Hands the screenshot to the app's TranslationSession-backed workflow.
/// TranslationSession is provided by SwiftUI's translationTask and cannot be
/// initialized directly from an AppIntent.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription("Translates the screenshot and opens the finished image preview.")
    static var openAppWhenRun = true

    @Parameter(
        title: "Screenshot",
        description: "Connect this to the Take Screenshot action directly above it.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \.$screenshot")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try PendingScreenshotStore.save(screenshot.data)
        return .result(dialog: "Screenshot received. QuickTranslate is preparing the translated image preview.")
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
        AppShortcut(intent: TranslateLatestScreenshotIntent(),
            phrases: ["Translate my screenshot with \(.applicationName)", "Translate screen with \(.applicationName)"],
            shortTitle: "Translate Screenshot", systemImageName: "text.viewfinder")
        AppShortcut(intent: OpenQuickTranslateIntent(),
            phrases: ["Open \(.applicationName)"], shortTitle: "Open QuickTranslate",
            systemImageName: "translate")
    }
}
