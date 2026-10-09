import Foundation

struct AppSettings: Codable {
    // Umum
    var downloadDirectory: String = (NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? NSHomeDirectory() + "/Downloads")
    var launchAtLoginNote: Bool = false
    var showFirstRunNotice: Bool = true
    var notifyCompleted: Bool = true
    var notifyFailed: Bool = true
    var slowMode: Bool = false
    /// Matikan komputer 60 detik setelah semua unduhan selesai.
    var shutdownWhenDone: Bool = false
    /// Ambil cookie langsung dari browser untuk video (yt-dlp
    /// --cookies-from-browser). "" = mati. Cth: "chrome".
    /// Berguna untuk link yang ditempel manual (tanpa lewat ekstensi).
    var cookiesFromBrowser: String = ""
    // Unduhan
    var maxConcurrentDownloads: Int = 3
    var segmentsPerDownload: Int = 8
    var globalSpeedLimitKBps: Int = 0 // 0 = tanpa batas
    var duplicateBehavior: String = "rename" // overwrite | rename | skip
    // Video
    var defaultQuality: MediaQuality = .best
    var defaultContainer: MediaVideoContainer = .mp4
    var defaultVideoCodec: MediaVideoCodec = .auto
    var defaultAudioFormat: MediaAudioFormat = .mp3
    var defaultAudioOnly: Bool = false
    var defaultSubtitleLangs: [String] = []
    var defaultEmbedSubtitle: Bool = false
    // Torrent
    var torrentPort: Int = 6881
    var torrentDownloadLimitKBps: Int = 0
    var torrentUploadLimitKBps: Int = 0
    var torrentDHT: Bool = true
    var torrentPEX: Bool = true
    var torrentEncryption: Bool = true
    var torrentSeedRatioLimit: Double = 1.0
    var handleMagnetLinks: Bool = true
    var handleTorrentFiles: Bool = true
    // Jaringan
    var customHeaders: [String: String] = [:]
    var cookies: String = ""
    var httpUsername: String = ""
    var httpPassword: String = ""

    static var `default`: AppSettings { AppSettings() }

    // Decoding toleran: settings lama yang belum punya field baru tetap terbaca
    // (field hilang → nilai default), bukan gagal total.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        downloadDirectory = try c.decodeIfPresent(String.self, forKey: .downloadDirectory) ?? d.downloadDirectory
        launchAtLoginNote = try c.decodeIfPresent(Bool.self, forKey: .launchAtLoginNote) ?? d.launchAtLoginNote
        showFirstRunNotice = try c.decodeIfPresent(Bool.self, forKey: .showFirstRunNotice) ?? d.showFirstRunNotice
        notifyCompleted = try c.decodeIfPresent(Bool.self, forKey: .notifyCompleted) ?? d.notifyCompleted
        notifyFailed = try c.decodeIfPresent(Bool.self, forKey: .notifyFailed) ?? d.notifyFailed
        slowMode = try c.decodeIfPresent(Bool.self, forKey: .slowMode) ?? d.slowMode
        shutdownWhenDone = try c.decodeIfPresent(Bool.self, forKey: .shutdownWhenDone) ?? d.shutdownWhenDone
        cookiesFromBrowser = try c.decodeIfPresent(String.self, forKey: .cookiesFromBrowser) ?? d.cookiesFromBrowser
        maxConcurrentDownloads = try c.decodeIfPresent(Int.self, forKey: .maxConcurrentDownloads) ?? d.maxConcurrentDownloads
        segmentsPerDownload = try c.decodeIfPresent(Int.self, forKey: .segmentsPerDownload) ?? d.segmentsPerDownload
        globalSpeedLimitKBps = try c.decodeIfPresent(Int.self, forKey: .globalSpeedLimitKBps) ?? d.globalSpeedLimitKBps
        duplicateBehavior = try c.decodeIfPresent(String.self, forKey: .duplicateBehavior) ?? d.duplicateBehavior
        defaultQuality = try c.decodeIfPresent(MediaQuality.self, forKey: .defaultQuality) ?? d.defaultQuality
        defaultContainer = try c.decodeIfPresent(MediaVideoContainer.self, forKey: .defaultContainer) ?? d.defaultContainer
        defaultVideoCodec = try c.decodeIfPresent(MediaVideoCodec.self, forKey: .defaultVideoCodec) ?? d.defaultVideoCodec
        defaultAudioFormat = try c.decodeIfPresent(MediaAudioFormat.self, forKey: .defaultAudioFormat) ?? d.defaultAudioFormat
        defaultAudioOnly = try c.decodeIfPresent(Bool.self, forKey: .defaultAudioOnly) ?? d.defaultAudioOnly
        defaultSubtitleLangs = try c.decodeIfPresent([String].self, forKey: .defaultSubtitleLangs) ?? d.defaultSubtitleLangs
        defaultEmbedSubtitle = try c.decodeIfPresent(Bool.self, forKey: .defaultEmbedSubtitle) ?? d.defaultEmbedSubtitle
        torrentPort = try c.decodeIfPresent(Int.self, forKey: .torrentPort) ?? d.torrentPort
        torrentDownloadLimitKBps = try c.decodeIfPresent(Int.self, forKey: .torrentDownloadLimitKBps) ?? d.torrentDownloadLimitKBps
        torrentUploadLimitKBps = try c.decodeIfPresent(Int.self, forKey: .torrentUploadLimitKBps) ?? d.torrentUploadLimitKBps
        torrentDHT = try c.decodeIfPresent(Bool.self, forKey: .torrentDHT) ?? d.torrentDHT
        torrentPEX = try c.decodeIfPresent(Bool.self, forKey: .torrentPEX) ?? d.torrentPEX
        torrentEncryption = try c.decodeIfPresent(Bool.self, forKey: .torrentEncryption) ?? d.torrentEncryption
        torrentSeedRatioLimit = try c.decodeIfPresent(Double.self, forKey: .torrentSeedRatioLimit) ?? d.torrentSeedRatioLimit
        handleMagnetLinks = try c.decodeIfPresent(Bool.self, forKey: .handleMagnetLinks) ?? d.handleMagnetLinks
        handleTorrentFiles = try c.decodeIfPresent(Bool.self, forKey: .handleTorrentFiles) ?? d.handleTorrentFiles
        customHeaders = try c.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? d.customHeaders
        cookies = try c.decodeIfPresent(String.self, forKey: .cookies) ?? d.cookies
        httpUsername = try c.decodeIfPresent(String.self, forKey: .httpUsername) ?? d.httpUsername
        httpPassword = try c.decodeIfPresent(String.self, forKey: .httpPassword) ?? d.httpPassword
    }
}
