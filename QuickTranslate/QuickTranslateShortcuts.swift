import AppIntents
import Photos
import Vision

/// Finds the newest screenshot in Photos and extracts its readable text.
/// No file parameter is exposed, so Shortcuts won't show a file picker.
struct ExtractTextFromScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Latest Screenshot"
    static var description = IntentDescription(
        "Finds your most recent screenshot in Photos, recognizes its text, and makes it available to the Translate and Quick Look actions."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some ReturnsValue<String> {
        let imageData = try await latestScreenshotData()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(data: imageData)
        try handler.perform([request])

        let observations = request.results ?? []
        let recognizedText = observations
            .sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        guard !recognizedText.isEmpty else {
            throw NSError(
                domain: "QuickTranslate",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No readable text was found in your latest screenshot."]
            )
        }

        return .result(value: recognizedText)
    }

    private func latestScreenshotData() async throws -> Data {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard authorization == .authorized || authorization == .limited else {
            throw NSError(
                domain: "QuickTranslate",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Allow QuickTranslate access to Photos so it can find your latest screenshot."]
            )
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.fetchLimit = 1

        guard let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject else {
            throw NSError(
                domain: "QuickTranslate",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No screenshot was found in your Photos library."]
            )
        }

        let imageData: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) -> Void in
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = false
            requestOptions.version = .current
            requestOptions.deliveryMode = .highQualityFormat

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: requestOptions
            ) { (data: Data?, dataUTI: String?, orientation: CGImagePropertyOrientation, info: [AnyHashable: Any]?) in
                let error = info?[PHImageErrorKey] as? Error
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(
                        throwing: error ?? NSError(
                            domain: "QuickTranslate",
                            code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "Could not load your latest screenshot."]
                        )
                    )
                }
            }
        }
        return imageData
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
            intent: ExtractTextFromScreenshotIntent(),
            phrases: ["Translate my latest screenshot with \\(.applicationName)"],
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
