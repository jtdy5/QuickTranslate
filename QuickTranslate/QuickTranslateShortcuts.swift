import AppIntents

/// Opens QuickTranslate. The app itself fetches the newest screenshot from Photos.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Latest Screenshot"
    static var description = IntentDescription(
        "Opens QuickTranslate and automatically translates the newest screenshot in your Photos library."
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "QuickTranslateShouldLoadLatestScreenshot")
        .result()
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
                "Translate my latest screenshot with \\(.applicationName)",
                "Translate latest screenshot using \\(.applicationName)"
            ],
            shortTitle: "Translate Latest Screenshot",
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
