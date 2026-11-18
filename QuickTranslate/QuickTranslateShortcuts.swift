import AppIntents
import UniformTypeIdentifiers

private func pendingScreenshotURL() throws -> URL {
    let directory = try FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    return directory.appendingPathComponent("QuickTranslate-pending-screenshot")
}

private func pendingTargetLanguageURL() throws -> URL {
    let directory = try FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    return directory.appendingPathComponent("QuickTranslate-target-language")
}

/// Hands the screenshot to QuickTranslate and opens the app, where OCR,
/// language detection, translation, and image rendering happen together.
struct TranslateScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription(
        "Opens QuickTranslate and automatically creates a translated image from the supplied screenshot."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Screenshot",
        description: "The screenshot to translate.",
        supportedContentTypes: [.image]
    )
    var screenshot: IntentFile

    @Parameter(title: "Translate to", default: "en")
    var targetLanguage: String

    func perform() async throws -> some IntentResult {
        try screenshot.data.write(to: pendingScreenshotURL(), options: .atomic)
        try targetLanguage.write(to: pendingTargetLanguageURL(), atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: Notification.Name("QuickTranslateProcessPendingScreenshot"), object: nil)
        return .result()
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
            intent: TranslateScreenshotIntent(),
            phrases: ["Translate my latest screenshot with \(.applicationName)"],
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
