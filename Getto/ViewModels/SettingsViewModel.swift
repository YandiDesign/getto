import Foundation
import Combine

/// Jembatan Settings UI <-> AppSettings (Codable) di QueueManager.
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet { QueueManager.shared.settings = settings }
    }
    @Published var nativeHostStatus: String = ""
    @Published var ytDlpVersion: String = ""

    init() {
        settings = QueueManager.shared.settings
        refreshNativeHostStatus()
    }

    func refreshNativeHostStatus() {
        nativeHostStatus = NativeHostInstaller.isInstalled()
            ? NSLocalizedString("browser.installed", value: "Terpasang", comment: "")
            : NSLocalizedString("browser.notInstalled", value: "Belum dipasang", comment: "")
    }

    func installNativeHost(extensionID: String) {
        let ok = NativeHostInstaller.install(extensionID: extensionID)
        refreshNativeHostStatus()
        Logger.log("NativeHost install: \(ok)")
    }

    /// Terapkan bahasa (id/en/sistem) via AppleLanguages per-app.
    /// Berlaku penuh setelah aplikasi dimulai ulang.
    func applyLanguage(_ lang: String) {
        if lang == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        Logger.log("language -> \(lang)")
    }

    func updateYtDlp() {
        Task {
            do {
                let out = try await MediaEngine.shared.updateEngine()
                await MainActor.run { self.ytDlpVersion = out }
            } catch {
                await MainActor.run { self.ytDlpVersion = error.localizedDescription }
            }
        }
    }

    func checkYtDlpVersion() {
        Task {
            guard let ytDlp = EngineProcessManager.shared.binaryPath(named: "yt-dlp") else { return }
            let (out, _) = (try? await EngineProcessManager.shared.runOnce(executable: ytDlp, arguments: ["--version"])) ?? ("—", 0)
            await MainActor.run { self.ytDlpVersion = out.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }
}
