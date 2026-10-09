import Foundation

/// Memasang manifest Native Messaging ke Chrome/Chromium/Brave/Edge
/// saat pertama dijalankan atau lewat tombol "Pasang integrasi".
enum NativeHostInstaller {
    static let hostName = "com.getto.host"

    static var browserPaths: [(name: String, dir: String)] {
        let home = NSHomeDirectory()
        return [
            ("Chrome", "\(home)/Library/Application Support/Google/Chrome/NativeMessagingHosts"),
            ("Chromium", "\(home)/Library/Application Support/Chromium/NativeMessagingHosts"),
            ("Brave", "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"),
            ("Edge", "\(home)/Library/Application Support/Microsoft Edge/NativeMessagingHosts"),
            ("Arc", "\(home)/Library/Application Support/Arc/User Data/NativeMessagingHosts")
        ]
    }

    static let idDefaultsKey = "getto.extensionID"
    // ID stabil ekstensi (dari `key` di manifest — terverifikasi cocok).
    static let placeholderID = "anjndmaheigemhmlojnfbjnllcddokdl"

    /// ID terakhir yang dipasang via tombol (tersimpan antar launch).
    static var savedExtensionID: String {
        UserDefaults.standard.string(forKey: idDefaultsKey) ?? placeholderID
    }

    /// Tulis manifest ke semua browser. Kembalikan daftar yang berhasil.
    /// ID ikut disimpan agar launch berikutnya bisa repair path tanpa
    /// menimpa ID (bug lama: selalu ditulis ulang dengan ID contoh).
    @discardableResult
    static func install(extensionID: String) -> [String] {
        let id = extensionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return [] }
        UserDefaults.standard.set(id, forKey: idDefaultsKey)
        return writeManifest(extensionID: id)
    }

    /// Repair saat launch: tulis ulang manifest HANYA bila belum ada atau
    /// path binary-nya sudah tidak cocok (app pindah folder). ID tersimpan
    /// tidak pernah ditimpa di sini.
    static func repairIfNeeded() {
        guard let hostBinary = currentHostBinary() else { return }
        var needsWrite = false
        for (_, dir) in browserPaths {
            let url = URL(fileURLWithPath: (dir as NSString).appendingPathComponent("\(hostName).json"))
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let path = json["path"] as? String,
                  path == hostBinary.path,
                  let origins = json["allowed_origins"] as? [String],
                  origins == ["chrome-extension://\(savedExtensionID)/"] else {
                needsWrite = true
                break
            }
        }
        if needsWrite {
            Logger.log("NativeHost repair (path/ID berubah)")
            writeManifest(extensionID: savedExtensionID)
        }
    }

    private static func currentHostBinary() -> URL? {
        EngineProcessManager.shared.binaryPath(named: "GettoNativeHost")
            ?? Bundle.main.url(forAuxiliaryExecutable: "GettoNativeHost")
    }

    @discardableResult
    private static func writeManifest(extensionID: String) -> [String] {
        guard let hostBinary = currentHostBinary() else {
            Logger.log("NativeHost binary tidak ditemukan")
            return []
        }
        var ok: [String] = []
        for (name, dir) in browserPaths {
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let manifest: [String: Any] = [
                    "name": hostName,
                    "description": "Getto download manager native host",
                    "path": hostBinary.path,
                    "type": "stdio",
                    "allowed_origins": ["chrome-extension://\(extensionID)/"]
                ]
                let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL(fileURLWithPath: (dir as NSString).appendingPathComponent("\(hostName).json")), options: .atomic)
                ok.append(name)
                Logger.log("NativeHost dipasang untuk \(name)")
            } catch {
                Logger.log("NativeHost gagal untuk \(name): \(error)")
            }
        }
        return ok
    }

    static func isInstalled() -> Bool {
        let fm = FileManager.default
        return browserPaths.contains { (_, dir) in
            fm.fileExists(atPath: (dir as NSString).appendingPathComponent("\(hostName).json"))
        }
    }
}
