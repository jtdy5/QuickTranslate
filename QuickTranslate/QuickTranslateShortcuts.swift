import AppIntents

struct OpenQuickTranslateIntent: AppIntent {
    static var title: LocalizedStringResource = "Open QuickTranslate"
    static var description = IntentDescription("Opens QuickTranslate.")

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct QuickTranslateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuickTranslateIntent(),
            phrases: ["Open QuickTranslate"],
            shortTitle: "QuickTranslate",
            systemImageName: "translate"
        )
    }
}
