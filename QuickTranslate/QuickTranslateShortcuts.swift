import AppIntents
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Transfers the screenshot from Shortcuts to the foreground app without
/// asking the user to pick a file or searching the Photos library.
enum PendingScreenshotStore {
    private static var fileURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickTranslate-pending-screenshot")
    }

    static func save(_ data: Data) throws {
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    static func take() -> Data? {
        defer { try? FileManager.default.removeItem(at: fileURL) }
        return try? Data(contentsOf: fileURL)
    }
}

struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription(
        "Receives the screenshot from the action above, then opens QuickTranslate and displays the translated image."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Screenshot",
        description: "Connect this to the Take Screenshot action directly above it.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$screenshot)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try PendingScreenshotStore.save(screenshot.data)
        UserDefaults.standard.set(true, forKey: "QuickTranslateHasPendingScreenshot")
        return .result(dialog: "Opening QuickTranslate to translate your screenshot.")
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
                "Translate my screenshot with \(.applicationName)",
                "Translate screen with \(.applicationName)"
            ],
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
