import Foundation

/// Penyimpanan state ke disk (JSON di Application Support) agar antrean
/// dan progres pulih setelah aplikasi ditutup/dibuka lagi.
final class PersistenceStore {
    static let shared = PersistenceStore()

    private var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Getto", isDirectory: true)
    }
    private var queueURL: URL { baseURL.appendingPathComponent("queue.json") }
    private var settingsURL: URL { baseURL.appendingPathComponent("settings.json") }

    private init() {
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    // MARK: - Queue

    func saveQueue(_ items: [DownloadItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: queueURL, options: .atomic)
        } catch {
            Logger.log("saveQueue gagal: \(error)")
        }
    }

    func loadQueue() -> [DownloadItem] {
        guard let data = try? Data(contentsOf: queueURL),
              let items = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return [] }
        // Unduhan yang sedang berjalan saat app ditutup → kembalikan ke antre agar bisa dilanjutkan.
        return items.map { item in
            var it = item
            if it.status == .downloading { it.status = .queued }
            return it
        }
    }

    // MARK: - Settings

    func saveSettings(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            Logger.log("saveSettings gagal: \(error)")
        }
    }

    func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return .default }
        return s
    }
}
