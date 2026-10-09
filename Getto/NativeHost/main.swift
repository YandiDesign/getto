import AppKit
import Foundation

/// Native Messaging host untuk ekstensi Chrome (Manifest V3).
/// Protokol: stdin/stdout dengan prefix panjang 4-byte little-endian (uint32) + JSON.
/// Pesan dari ekstensi: {"action":"add","url":"...","cookies":"...","referer":"..."}
/// Balasan: {"ok":true,"message":"..."}
///
/// Binary ini dibundel di Contents/MacOS/GettoNativeHost dan didaftarkan lewat
/// manifest com.getto.host.json oleh NativeHostInstaller.
///
/// Validasi pemanggil dilakukan oleh browser lewat `allowed_origins` di manifest
/// (ID ekstensi stabil, sama dengan `key` di manifest.json):
/// `anjndmaheigemhmlojnfbjnllcddokdl`.

func readMessage() -> [String: Any]? {
    let stdin = FileHandle.standardInput
    let lenData = stdin.readData(ofLength: 4)
    guard lenData.count == 4 else { return nil }
    let len: UInt32 = lenData.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    guard len > 0 && len < 10 * 1024 * 1024 else { return nil }
    let payload = stdin.readData(ofLength: Int(len))
    guard payload.count == Int(len) else { return nil }
    return (try? JSONSerialization.jsonObject(with: payload) as? [String: Any])
}

func writeMessage(_ dict: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
    var len = UInt32(data.count).littleEndian
    let header = Data(bytes: &len, count: 4)
    FileHandle.standardOutput.write(header)
    FileHandle.standardOutput.write(data)
}

/// Ubah profil browser dari ekstensi menjadi header HTTP, lalu encode
/// base64(JSON) agar aman melalui query string URL scheme.
func encodeProfile(_ profile: [String: Any]) -> String? {
    var headers: [String: String] = [:]
    if let ua = profile["userAgent"] as? String,
       !ua.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        headers["User-Agent"] = ua
    }
    if let acc = profile["accept"] as? String,
       !acc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        headers["Accept"] = acc
    }
    if let lang = profile["acceptLanguage"] as? String,
       !lang.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        headers["Accept-Language"] = lang
    }
    if let hints = profile["hints"] as? [String: String] {
        for (k, v) in hints where !k.isEmpty && !v.isEmpty { headers[k] = v }
    }
    guard !headers.isEmpty,
          let data = try? JSONSerialization.data(withJSONObject: headers) else { return nil }
    return data.base64EncodedString()
}

func handleAdd(urlString: String, cookies: String?, referer: String?, profile: [String: Any]? = nil) -> [String: Any] {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ["ok": false, "message": "URL kosong"] }
    // Teruskan ke aplikasi via URL scheme getto://add (bekerja walau app belum terbuka —
    // macOS akan meluncurkan Getto yang menangani scheme tersebut).
    // Cookies + referer + profil browser (UA & client hint asli) ikut
    // diteruskan: cookie sesi situs hanya sah bila UA-nya sama dengan
    // browser yang menerbitkannya (mis. `cf_clearance` Cloudflare).
    var comps = URLComponents(string: "getto://add")!
    var items = [URLQueryItem(name: "url", value: trimmed)]
    if let c = cookies?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
        items.append(URLQueryItem(name: "cookies", value: c))
    }
    if let r = referer?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
        items.append(URLQueryItem(name: "referer", value: r))
    }
    if let profile = profile, !profile.isEmpty,
       let encoded = encodeProfile(profile) {
        items.append(URLQueryItem(name: "h", value: encoded))
    }
    comps.queryItems = items
    guard let url = comps.url else { return ["ok": false, "message": "URL tidak valid"] }
    let workspace = NSWorkspace.shared
    // Buka via Getto bundle id bila terinstal, fallback open default (LaunchServices route ke handler getto:)
    if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.getto.app") {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let sema = DispatchSemaphore(value: 0)
        var ok = false
        workspace.open([url], withApplicationAt: appURL, configuration: config) { _, error in
            ok = (error == nil)
            sema.signal()
        }
        sema.wait()
        return ok ? ["ok": true, "message": "Dikirim ke Getto"] : ["ok": false, "message": "Gagal membuka Getto"]
    } else {
        workspace.open(url)
        return ["ok": true, "message": "Dikirim ke Getto"]
    }
}

// Loop utama: baca pesan sampai EOF (Chrome menutup stdin saat extension di-unload).
while let msg = readMessage() {
    let action = msg["action"] as? String ?? "add"
    if action == "ping" {
        writeMessage(["ok": true, "message": "pong", "version": "1.0"])
        continue
    }
    if action == "add" {
        let url = msg["url"] as? String ?? msg["pageUrl"] as? String ?? ""
        let resp = handleAdd(urlString: url,
                             cookies: msg["cookies"] as? String,
                             referer: msg["referer"] as? String,
                             profile: msg["profile"] as? [String: Any])
        writeMessage(resp)
        continue
    }
    writeMessage(["ok": false, "message": "Aksi tidak dikenal: \(action)"])
}
