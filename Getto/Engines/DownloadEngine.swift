import Foundation

/// Protokol umum agar mesin unduh bisa diganti tanpa mengubah UI.
protocol DownloadEngine: AnyObject {
    /// Tambah unduhan baru, kembalikan ID internal engine (mis. aria2 gid).
    /// headers: header HTTP kustom (Cookie/Referer dari browser, auth, dsb).
    func add(urlString: String, fileName: String, destinationDirectory: String, segments: Int, headers: [String: String]) async throws -> String
    func pause(engineId: String) async throws
    func resume(engineId: String) async throws
    func cancel(engineId: String) async throws
    /// Status terkini; kembalikan nil bila gid sudah tidak dikenal (selesai & dibersihkan).
    func status(engineId: String) async throws -> EngineStatus?
}

struct EngineStatus {
    var totalBytes: Int64
    var downloadedBytes: Int64
    var speedBytesPerSec: Int64
    var etaSeconds: Int64
    var numSeeds: Int
    var numPeers: Int
    var uploadSpeed: Int64
    var isComplete: Bool
    var errorMessage: String?
}

enum EngineError: LocalizedError {
    case binaryNotFound(String)
    case launchFailed(String)
    case rpcFailed(String)
    case invalidURL
    case userFriendly(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let n): return String(format: NSLocalizedString("err.nobinary", value: "Mesin %@ tidak ditemukan di dalam aplikasi. Instal ulang Getto.", comment: ""), n)
        case .launchFailed(let s): return String(format: NSLocalizedString("err.launch", value: "Gagal menjalankan mesin: %@", comment: ""), s)
        case .rpcFailed(let s): return String(format: NSLocalizedString("err.rpc", value: "Komunikasi mesin gagal: %@", comment: ""), s)
        case .invalidURL: return NSLocalizedString("err.invalidurl", value: "Tautan tidak valid. Periksa kembali URL-nya.", comment: "")
        case .userFriendly(let s): return s
        }
    }
}

/// Deteksi halaman tantangan Cloudflare ("Just a moment...") dari cuplikan body.
/// Murni (bisa diuji): true bila status khas Cloudflare DAN ada penanda.
func isCloudflareChallenge(statusCode: Int, bodySnippet: String) -> Bool {
    // Beberapa situs membalas 200/429 untuk interstitial yang sama, jadi jangan
    // hanya andalkan status 403/503.
    guard [200, 401, 403, 429, 503].contains(statusCode) else { return false }
    let b = bodySnippet.lowercased()
    let markers = ["just a moment", "challenges.cloudflare.com", "cf_chl", "cf-chl",
                   "cf-browser-verification", "challenge-platform", "cloudflare ray id",
                   "attention required! | cloudflare", "enable javascript and cookies"]
    return markers.contains { b.contains($0) }
}

/// True bila pesan error aria2/IPC menandakan penolakan akses (403/401/…)
    /// — dipakai sebagai pemicu verifikasi Cloudflare.
func looksLikeAccessDenied(_ message: String) -> Bool {
    let m = message.lowercased()
    let needles = ["403", "401", "access denied", "forbidden", "authorization failed",
                   "unauthorized", "not authorized", "permission denied"]
    return needles.contains { m.contains($0) }
}

/// Normalisasi link Google Drive menjadi URL download langsung.
/// File besar Drive menampilkan halaman konfirmasi virus-scan bila tanpa
/// `confirm=t` (hasilnya halaman HTML kecil, bukan file) — tidak ada batasan
/// ukuran di Getto; yang gagal itu interstisialnya. Murni (bisa diuji).
/// - drive.google.com/file/d/<id>/... → uc?export=download&id=<id>&confirm=t
/// - drive.google.com/uc?export=download&id=<id> → tambah confirm=t bila belum ada
/// - drive.google.com/open?id=<id> → bentuk uc + confirm=t
/// - drive.usercontent.google.com/download?id=<id> → tambah confirm=t bila belum ada
/// - bukan Drive → nil
func googleDriveDirectURL(_ raw: String) -> String? {
    guard var comps = URLComponents(string: raw),
          let host = comps.host?.lowercased() else { return nil }
    let isDrive = host == "drive.google.com" || host.hasSuffix(".drive.google.com")
    let isUserContent = host == "drive.usercontent.google.com"
    guard isDrive || isUserContent else { return nil }
    let items = comps.queryItems ?? []
    func q(_ name: String) -> String? {
        items.first(where: { $0.name == name })?.value
    }
    func withConfirm(_ base: String, id: String, extra: [URLQueryItem] = []) -> String? {
        var c = URLComponents(string: base)!
        c.queryItems = [URLQueryItem(name: "export", value: "download"),
                        URLQueryItem(name: "id", value: id),
                        URLQueryItem(name: "confirm", value: "t")] + extra
        return c.url?.absoluteString
    }
    if isDrive {
        // /file/d/<id>/...
        let parts = comps.path.split(separator: "/").map(String.init)
        if parts.count >= 3, parts[0] == "file", parts[1] == "d" {
            let id = parts[2]
            guard !id.isEmpty else { return nil }
            return withConfirm("https://drive.google.com/uc", id: id)
        }
        if comps.path == "/open", let id = q("id"), !id.isEmpty {
            return withConfirm("https://drive.google.com/uc", id: id)
        }
    }
    // /uc atau /download yang kurang confirm=t (sertakan param lain apa adanya).
    // /uc butuh export=download; /download usercontent langsung mengunduh.
    if (comps.path == "/uc" || comps.path == "/download"),
       let id = q("id"), !id.isEmpty,
       comps.path == "/download" || (q("export") ?? "") == "download",
       q("confirm") == nil {
        comps.queryItems = (items + [URLQueryItem(name: "confirm", value: "t")])
        return comps.url?.absoluteString
    }
    return nil
}
func friendlyErrorMessage(_ raw: String) -> String {
    let t = { (key: String, fallback: String) in NSLocalizedString(key, value: fallback, comment: "") }
    let r = raw.lowercased()
    if r.contains("private video") || r.contains("login required") { return t("err.private", "Video ini privat atau butuh login.") }
    if r.contains("unsupported url") || r.contains("no video formats") { return t("err.unsupported", "Situs ini tidak didukung atau tidak ada media yang bisa diunduh.") }
    if r.contains("no space") || r.contains("disk penuh") { return t("err.diskfull", "Disk penuh. Bebaskan ruang lalu coba lagi.") }
    if r.contains("timed out") || r.contains("network is unreachable") { return t("err.network", "Jaringan bermasalah. Periksa koneksi lalu coba lagi.") }
    if r.contains("not a bot") || r.contains("sign in to confirm") { return t("err.botcheck", "YouTube meminta verifikasi anti-bot. Tunggu beberapa saat lalu coba lagi, atau isi cookie login di Pengaturan → Jaringan.") }
    if r.contains("404") { return t("err.404", "File tidak ditemukan (404). Tautan mungkin kedaluwarsa.") }
    if r.contains("403") || r.contains("401") { return t("err.403", "Akses ditolak. Mungkin perlu login/cookie — isi bagian Lanjutan.") }
    return raw
}
