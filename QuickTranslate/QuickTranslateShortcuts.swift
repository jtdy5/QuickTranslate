import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Receives a screenshot, translates it with Apple's on-device frameworks,
/// and returns a self-contained HTML document with an in-preview image toggle.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Screenshot"
    static var description = IntentDescription("Translate the screenshot supplied by the preceding Shortcut action.")
    static var openAppWhenRun = false

    @Parameter(
        title: "Screenshot",
        description: "Image produced by the preceding Take Screenshot action.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$screenshot) to English")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let originalData = screenshot.data
        let translatedData = try await ImageTranslationProcessor.translate(
            originalData,
            targetLanguage: "en"
        )
        let html = Self.makeTogglePreview(
            original: originalData,
            translated: translatedData
        )
        let output = IntentFile(
            data: Data(html.utf8),
            filename: "QuickTranslate-Preview.html",
            type: .html
        )
        return .result(value: output)
    }

    private static func makeTogglePreview(original: Data, translated: Data) -> String {
        let originalImage = original.base64EncodedString()
        let translatedImage = translated.base64EncodedString()
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5">
          <meta charset="utf-8">
          <title>QuickTranslate</title>
          <style>
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; background: #111; color: #fff; font-family: -apple-system, sans-serif; }
            .toolbar { position: fixed; left: 50%; bottom: max(18px, env(safe-area-inset-bottom)); transform: translateX(-50%); z-index: 2; display: flex; justify-content: center; gap: 5px; padding: 5px; border-radius: 20px; background: rgba(25,25,25,.82); }
            input { position: absolute; opacity: 0; pointer-events: none; }
            label { padding: 6px 11px; border: 1px solid #777; border-radius: 15px; color: #eee; cursor: pointer; font-size: 12px; line-height: 1.2; }
            #translated:checked ~ .toolbar label[for="translated"],
            #original:checked ~ .toolbar label[for="original"] { background: #fff; color: #111; border-color: #fff; }
            .image { display: none; width: 100%; height: auto; }
            #original:checked ~ .images .original,
            #translated:checked ~ .images .translated { display: block; }
            .images { padding: 0 0 58px; text-align: center; }
          </style>
        </head>
        <body>
          <input type="radio" name="view" id="original">
          <input type="radio" name="view" id="translated" checked>
          <div class="toolbar">
            <label for="original">Original</label>
            <label for="translated">Translation</label>
          </div>
          <main class="images">
            <img class="image original" alt="Original screenshot" src="data:image/png;base64,\(originalImage)">
            <img class="image translated" alt="Translated screenshot" src="data:image/png;base64,\(translatedImage)">
          </main>
        </body>
        </html>
        """
    }
}

struct QuickTranslateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateLatestScreenshotIntent(),
            phrases: ["Translate my screenshot with \(.applicationName)", "Translate screen with \(.applicationName)"],
            shortTitle: "Translate Screenshot",
            systemImageName: "text.viewfinder"
        )
    }
}
