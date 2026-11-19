import AppIntents
import Foundation
import Photos
import UniformTypeIdentifiers

/// Finds the newest screenshot in Photos, translates it on-device, and returns
/// the finished PNG. The user only needs to run this one Shortcut action.
struct TranslateLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Latest Screenshot"
    static var description = IntentDescription("Automatically finds your newest screenshot, translates it to English offline, and returns the translated image. No image picker or extra Shortcut actions are needed.")
    static var openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Translate the latest screenshot to English")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let screenshotData = try await Self.fetchLatestScreenshot()
        let pngData = try await ImageTranslationProcessor.translate(
            screenshotData,
            targetLanguage: "en"
        )
        let output = IntentFile(data: pngData, filename: "QuickTranslate-Translated.png", type: .png)
        return .result(value: output)
    }

    private static func fetchLatestScreenshot() async throws -> Data {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard authorization == .authorized || authorization == .limited else {
            throw ShortcutError.photoAccessDenied
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard let asset = assets.firstObject else {
            throw ShortcutError.noScreenshot
        }

        return try await withCheckedThrowingContinuation { continuation in
            let requestOptions = PHImageRequestOptions()
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.version = .current
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: requestOptions
            ) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ShortcutError.unreadableScreenshot)
                }
            }
        }
    }

    private enum ShortcutError: LocalizedError {
        case photoAccessDenied
        case noScreenshot
        case unreadableScreenshot

        var errorDescription: String? {
            switch self {
            case .photoAccessDenied:
                return "Allow QuickTranslate to access your Photos so it can find the latest screenshot. You only need to grant this once."
            case .noScreenshot:
                return "No screenshots were found in Photos. Take a screenshot first, then run this shortcut again."
            case .unreadableScreenshot:
                return "The latest screenshot couldn't be read. Try taking a new screenshot."
            }
        }
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
            phrases: ["Translate my latest screenshot with \\.applicationName", "Translate screen with \\.applicationName"],
            shortTitle: "Translate Latest Screenshot",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: OpenQuickTranslateIntent(),
            phrases: ["Open \\.applicationName"],
            shortTitle: "Open QuickTranslate",
            systemImageName: "translate"
        )
    }
}
