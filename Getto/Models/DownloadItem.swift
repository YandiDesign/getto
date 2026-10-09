import Foundation

// MARK: - Status & Jenis Unduhan

enum DownloadStatus: String, Codable, CaseIterable {
    case queued
    case downloading
    case paused
    case completed
    case failed
    case seeding
}

enum DownloadKind: String, Codable {
    case http
    case video
    case audio
    case torrent
}

enum SidebarSelection: String, Hashable, CaseIterable {
    case all
    case active
    case queued
    case completed
    case torrents
    case media
    case failed
    case documents
    case archives
    case images
    case music
    case videos
    case apps
}

// MARK: - DownloadItem

struct DownloadItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var urlString: String
    var fileName: String
    var destinationPath: String
    var kind: DownloadKind = .http
    var status: DownloadStatus = .queued
    var totalBytes: Int64 = 0
    var downloadedBytes: Int64 = 0
    var speedBytesPerSec: Int64 = 0
    var etaSeconds: Int64 = 0
    var createdAt: Date = Date()
    var completedAt: Date?
    var errorMessage: String?
    /// Engine-specific identifier (aria2 gid)
    var engineId: String?
    var numSeeds: Int = 0
    var numPeers: Int = 0
    var uploadSpeed: Int64 = 0
    var ratio: Double = 0
    var phaseDescription: String?
    /// Header HTTP kustom per item (Cookie dari browser, Referer, auth, dsb).
    /// Disimpan di antrean agar tetap dipakai setelah restart.
    var headers: [String: String] = [:]

    // Decoding toleran: antrean lama tanpa field baru tetap terbaca.
    init(urlString: String, fileName: String, destinationPath: String,
         kind: DownloadKind = .http, status: DownloadStatus = .queued,
         headers: [String: String] = [:]) {
        self.urlString = urlString
        self.fileName = fileName
        self.destinationPath = destinationPath
        self.kind = kind
        self.status = status
        self.headers = headers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        urlString = try c.decodeIfPresent(String.self, forKey: .urlString) ?? ""
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? "unduhan"
        destinationPath = try c.decodeIfPresent(String.self, forKey: .destinationPath) ?? ""
        kind = try c.decodeIfPresent(DownloadKind.self, forKey: .kind) ?? .http
        status = try c.decodeIfPresent(DownloadStatus.self, forKey: .status) ?? .queued
        totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        downloadedBytes = try c.decodeIfPresent(Int64.self, forKey: .downloadedBytes) ?? 0
        speedBytesPerSec = try c.decodeIfPresent(Int64.self, forKey: .speedBytesPerSec) ?? 0
        etaSeconds = try c.decodeIfPresent(Int64.self, forKey: .etaSeconds) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        engineId = try c.decodeIfPresent(String.self, forKey: .engineId)
        numSeeds = try c.decodeIfPresent(Int.self, forKey: .numSeeds) ?? 0
        numPeers = try c.decodeIfPresent(Int.self, forKey: .numPeers) ?? 0
        uploadSpeed = try c.decodeIfPresent(Int64.self, forKey: .uploadSpeed) ?? 0
        ratio = try c.decodeIfPresent(Double.self, forKey: .ratio) ?? 0
        phaseDescription = try c.decodeIfPresent(String.self, forKey: .phaseDescription)
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
    }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(downloadedBytes) / Double(totalBytes))
    }

    var isTorrent: Bool { kind == .torrent }
    var isMedia: Bool { kind == .video || kind == .audio }

    /// Kategori file untuk sidebar, berdasarkan ekstensi.
    var fileCategory: SidebarSelection {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "app", "dmg", "pkg", "iso":
            return .apps
        case "pdf", "doc", "docx", "txt", "rtf", "md", "xls", "xlsx", "ppt", "pptx", "csv", "epub":
            return .documents
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return .archives
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff", "bmp":
            return .images
        case "mp3", "m4a", "opus", "flac", "wav", "aac", "ogg":
            return .music
        case "mp4", "mkv", "webm", "mov", "avi":
            return .videos
        default:
            return .all
        }
    }

    /// Host situs asal (tanpa www.), untuk baris info Sumber.
    var websiteHost: String {
        guard let url = URL(string: urlString) else { return "—" }
        if url.scheme?.lowercased() == "magnet" { return "magnet" }
        if url.isFileURL {
            return NSLocalizedString("detail.localOnly", value: "Berkas lokal", comment: "")
        }
        guard let host = url.host, !host.isEmpty else { return "—" }
        return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    static func fileNameFrom(urlString: String) -> String {        guard let url = URL(string: urlString) else { return "unduhan" }
        let last = url.lastPathComponent
        if !last.isEmpty && last != "/" { return last.removingPercentEncoding ?? last }
        return url.host ?? "unduhan"
    }

    /// Sanitasi nama file: cegah path traversal & karakter ilegal.
    static func sanitizedFileName(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Hapus ".." untuk cegah traversal
        while s.contains("..") { s = s.replacingOccurrences(of: "..", with: "_") }
        if s.isEmpty { s = "unduhan" }
        // Batasi panjang (HFS+/APFS aman di 255 byte)
        if s.count > 200 { s = String(s.prefix(200)) }
        return s
    }
}
