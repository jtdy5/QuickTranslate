import Foundation

/// One-shot handoff between the Shortcuts App Intent and the app UI.
enum PendingScreenshotStore {
    private static let defaultsKey = "QuickTranslate.PendingScreenshot"

    static func save(_ data: Data) throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("QuickTranslate-Pending-Screenshot.png")
        try data.write(to: url, options: .atomic)
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
    }

    static func take() -> Data? {
        guard let path = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        let url = URL(fileURLWithPath: path)
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }
}
