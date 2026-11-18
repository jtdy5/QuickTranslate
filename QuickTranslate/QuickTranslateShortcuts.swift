import AppIntents
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Translates the screenshot directly inside Shortcuts and returns the finished
/// PNG as a file result for Quick Look or any following shortcut action.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription(
        "Translates the screenshot and returns the finished translated image."
    )
    static var openAppWhenRun: Bool = false

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
        let translatedFile = try await QuickTranslateShortcutPipeline.translate(screenshot.data)
        return .result(
            value: translatedFile,
            dialog: "Your translated screenshot is ready."
        )
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
            intent: TranslateLatestScreenshotIntent(),
            phrases: [
                "Translate my screenshot with \\(.applicationName)",
                "Translate screen with \\(.applicationName)"
            ],
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
