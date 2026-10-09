import Foundation

/// Pembungkus yt-dlp + ffmpeg untuk unduh video/audio.
/// - Pratinjau: `yt-dlp --dump-json --no-playlist <url>`
/// - Unduh: format mapping dari MediaOptions + merge via ffmpeg yang dibundel.
final class MediaEngine {
    static let shared = MediaEngine()
    private init() {}

    var ytDlpURL: URL? { EngineProcessManager.shared.binaryPath(named: "yt-dlp") }
    var ffmpegURL: URL? { EngineProcessManager.shared.binaryPath(named: "ffmpeg") }

    // MARK: - Pratinjau

    func fetchPreview(urlString: String) async throws -> MediaInfo {
        guard let ytDlp = ytDlpURL else { throw EngineError.binaryNotFound("yt-dlp") }
        let (out, code) = try await EngineProcessManager.shared.runOnce(
            executable: ytDlp,
            // Fail-fast: jangan retry berlama-lama untuk pratinjau sheet.
            arguments: ["--dump-json", "--no-playlist", "--no-warnings",
                        "--socket-timeout", "15", "--retries", "2", "--extractor-retries", "2",
                        urlString],
            timeout: 45
        )
        guard code == 0, let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EngineError.userFriendly(friendlyErrorMessage(out.isEmpty ? "Gagal membaca info video." : out))
        }
        return MediaInfo(
            videoId: json["id"] as? String ?? UUID().uuidString,
            title: json["title"] as? String ?? urlString,
            channel: json["channel"] as? String ?? json["uploader"] as? String,
            durationSeconds: (json["duration"] as? Int).map(Int64.init) ?? (json["duration"] as? Double).map(Int64.init),
            thumbnailURL: json["thumbnail"] as? String,
            extractor: json["extractor"] as? String,
            webpageURL: json["webpage_url"] as? String ?? urlString
        )
    }

    /// Daftar entri playlist/kanal (batasi 200 agar UI tetap ringan).
    func fetchPlaylistEntries(urlString: String) async throws -> [MediaInfo] {
        guard let ytDlp = ytDlpURL else { throw EngineError.binaryNotFound("yt-dlp") }
        let (out, code) = try await EngineProcessManager.shared.runOnce(
            executable: ytDlp,
            arguments: ["--flat-playlist", "--dump-json", "--no-warnings", urlString],
            timeout: 120
        )
        guard code == 0 else { throw EngineError.userFriendly(friendlyErrorMessage(out)) }
        var result: [MediaInfo] = []
        for line in out.components(separatedBy: .newlines) where line.hasPrefix("{") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            result.append(MediaInfo(
                videoId: json["id"] as? String ?? UUID().uuidString,
                title: json["title"] as? String ?? "(tanpa judul)",
                channel: json["channel"] as? String,
                durationSeconds: (json["duration"] as? Int).map(Int64.init),
                thumbnailURL: json["thumbnail"] as? String ?? json["thumbnails"] as? String,
                extractor: json["extractor"] as? String,
                webpageURL: json["url"] as? String ?? json["webpage_url"] as? String
            ))
            if result.count >= 200 { break }
        }
        return result
    }

    // MARK: - Unduh

    /// Jalankan unduhan; panggil `onProgress(terunduh, total, kecepatan, fase)` kumulatif
    /// selama berjalan (akumulasi antar segmen video+audio). Kembalikan URL file hasil.
    func download(
        urlString: String,
        options: MediaOptions,
        destinationDirectory: String,
        subtitleLangs: [String] = [],
        limitRateKBps: Int? = nil,
        headers: [String: String] = [:],
        cookiesFromBrowser: String = "",
        processHandler: ((Process) -> Void)? = nil,
        onProgress: @escaping (_ downloaded: Int64, _ total: Int64, _ speed: Int64, _ phase: String) -> Void
    ) async throws -> URL {
        guard let ytDlp = ytDlpURL else { throw EngineError.binaryNotFound("yt-dlp") }
        var args: [String] = ["--no-playlist", "--no-warnings", "--newline", "--progress"]
        // Header kustom per unduhan (Cookie/Referer browser, auth).
        for (key, value) in headers where !key.trimmingCharacters(in: .whitespaces).isEmpty {
            args += ["--add-headers", "\(key.trimmingCharacters(in: .whitespaces)): \(value)"]
        }
        // Cookie langsung dari browser (untuk link tempel manual).
        // Butuh akses keychain sekali saat pertama dipakai.
        if !cookiesFromBrowser.isEmpty {
            args += ["--cookies-from-browser", cookiesFromBrowser]
        }
        if options.audioOnly {
            args += ["--extract-audio", "--audio-format", options.audioFormat.rawValue]
        } else {
            let fmt = options.videoCodec == .h264 ? options.quality.h264Format : options.quality.ytDlpFormat
            args += ["--format", fmt,
                     "--merge-output-format", options.container.rawValue]
        }
        args += ["--embed-thumbnail", "--embed-metadata"]
        if !subtitleLangs.isEmpty {
            args += ["--sub-langs", subtitleLangs.joined(separator: ",")]
            args += options.embedSubtitle ? ["--embed-subs"] : ["--write-sub", "--sub-format", "srt"]
        }
        if let ffmpeg = ffmpegURL {
            args += ["--ffmpeg-location", ffmpeg.path]
        }
        // Slow mode: batasi ke 1 KB/s (pause semu untuk server yang tak bisa di-pause).
        if let limit = limitRateKBps, limit > 0 {
            args += ["--limit-rate", "\(limit)K"]
        }
        args += ["--output", (destinationDirectory as NSString).appendingPathComponent("%(title)s [%(id)s].%(ext)s")]
        args.append(urlString)

        return try await withCheckedThrowingContinuation { cont in
            do {
                // Box agar aman dibaca/ditulis dari callback pipe background.
                final class ProgressState { var base: Int64 = 0; var total: Int64 = 0; var errors: [String] = [] }
                let state = ProgressState()
                func report(_ pct: Double, _ speed: Int64, _ phase: String) {
                    let grand = state.base + state.total
                    let done = state.base + Int64(pct * Double(max(state.total, 0)))
                    onProgress(done, grand, speed, phase)
                }
                let proc = try EngineProcessManager.shared.launch(executable: ytDlp, arguments: args) { line in
                    let ph = { (key: String, fallback: String) in NSLocalizedString(key, value: fallback, comment: "") }
                    // Segmen baru (video, lalu audio): kunci total segmen lama sebagai basis.
                    if line.contains("[download] Destination:") {
                        if state.total > 0 { state.base += state.total }
                        state.total = 0
                    }
                    // Contoh: "[download]  42.1% of ~10.5MiB at 2.1MiB/s ETA 00:03"
                    if line.contains("[download]") && line.contains("%") {
                        let total = MediaEngine.parseTotalBytes(line: line)
                        if total > 0 { state.total = total }
                        report(MediaEngine.parseProgress(line: line), MediaEngine.parseSpeed(line: line), ph("phase.downloading", "Mengunduh"))
                    } else if line.contains("[Merger]") || line.contains("[Merge]") {
                        report(1.0, 0, ph("phase.merging", "Menggabungkan"))
                    } else if line.contains("[ExtractAudio]") {
                        report(1.0, 0, ph("phase.converting", "Mengonversi audio"))
                    } else if line.contains("[EmbedSubtitle]") || line.contains("[EmbedThumbnail]") || line.contains("[Metadata]") {
                        report(1.0, 0, ph("phase.meta", "Menyematkan metadata"))
                    }
                    if line.hasPrefix("ERROR:") {
                        state.errors.append(line)
                        if state.errors.count > 8 { state.errors.removeFirst() }
                    }
                    Logger.log("yt-dlp: \(line)")
                }
                // Daftarkan proses agar pause/cancel bisa menghentikannya.
                processHandler?(proc)
                proc.terminationHandler = { p in
                    if p.terminationStatus == 0 {
                        // Cari file hasil terbaru di direktori tujuan
                        let newest = MediaEngine.newestFile(in: destinationDirectory)
                        if let file = newest {
                            let grand = state.base + state.total
                            onProgress(grand, grand, 0, NSLocalizedString("phase.done", value: "Selesai", comment: ""))
                            cont.resume(returning: file)
                        } else {
                            cont.resume(throwing: EngineError.userFriendly(NSLocalizedString("err.noFile", value: "Unduhan selesai tetapi file hasil tidak ditemukan.", comment: "")))
                        }
                    } else {
                        let tail = state.errors.suffix(3).joined(separator: "\n")
                        let msg = tail.isEmpty
                            ? NSLocalizedString("err.videoFail", value: "Unduhan video gagal. Coba kualitas lain atau perbarui mesin yt-dlp.", comment: "")
                            : tail
                        cont.resume(throwing: EngineError.userFriendly(friendlyErrorMessage(msg)))
                    }
                }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    /// Perbarui yt-dlp ke rilis terbaru tanpa update aplikasi.
    func updateEngine() async throws -> String {
        guard let ytDlp = ytDlpURL else { throw EngineError.binaryNotFound("yt-dlp") }
        let (out, code) = try await EngineProcessManager.shared.runOnce(executable: ytDlp, arguments: ["-U"], timeout: 180)
        guard code == 0 else { throw EngineError.userFriendly(friendlyErrorMessage(out)) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private static func parseProgress(line: String) -> Double {
        // cari token "...% "
        for token in line.components(separatedBy: .whitespaces) where token.hasSuffix("%") {
            if let v = Double(token.dropLast()) { return min(1.0, max(0, v / 100.0)) }
        }
        return 0
    }

    private static func firstToken(_ s: String) -> String {
        // components(separatedBy:) menghasilkan token kosong untuk spasi ganda ("of   14.59MiB")
        s.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }

    /// Ambil total ukuran dari baris progres: "[download] 42.1% of ~10.5MiB at ..." -> bytes.
    /// Kembalikan 0 bila tak diketahui ("of Unknown").
    private static func parseTotalBytes(line: String) -> Int64 {
        guard let ofRange = line.range(of: " of ") else { return 0 }
        let after = String(line[ofRange.upperBound...])
        var token = firstToken(after)
        token = token.replacingOccurrences(of: "~", with: "")
        guard !token.isEmpty, token.lowercased() != "unknown" else { return 0 }
        let num = Double(token.filter { "0123456789.".contains($0) }) ?? 0
        guard num > 0 else { return 0 }
        if token.contains("GiB") { return Int64(num * 1024 * 1024 * 1024) }
        if token.contains("MiB") { return Int64(num * 1024 * 1024) }
        if token.contains("KiB") { return Int64(num * 1024) }
        return Int64(num)
    }

    private static func parseSpeed(line: String) -> Int64 {
        // "at 2.10MiB/s" -> bytes/s
        guard let atRange = line.range(of: "at ") else { return 0 }
        let after = String(line[atRange.upperBound...])
        let token = firstToken(after)
        let num = Double(token.filter { "0123456789.".contains($0) }) ?? 0
        if token.contains("GiB") { return Int64(num * 1024 * 1024 * 1024) }
        if token.contains("MiB") { return Int64(num * 1024 * 1024) }
        if token.contains("KiB") { return Int64(num * 1024) }
        return Int64(num)
    }

    private static func newestFile(in dir: String) -> URL? {
        let url = URL(fileURLWithPath: dir)
        let all = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        // Abaikan file sementara/thumbnail/subtitle; utamakan hasil media final.
        let tempExts: Set<String> = ["part", "ytdl", "temp", "tmp"]
        let mediaExts: Set<String> = ["mp4", "mkv", "webm", "mov", "avi", "mp3", "m4a", "opus", "flac", "wav", "ogg", "aac"]
        let thumbExts: Set<String> = ["webp", "jpg", "jpeg", "png"]
        let subExts: Set<String> = ["srt", "vtt", "ass", "lrc"]
        let usable = all.filter { tempExts.contains($0.pathExtension.lowercased()) == false }
        guard !usable.isEmpty else { return nil }
        let preferred = usable.filter {
            let e = $0.pathExtension.lowercased()
            return mediaExts.contains(e) && thumbExts.contains(e) == false && subExts.contains(e) == false
        }
        let pool = preferred.isEmpty ? usable : preferred
        return pool.sorted(by: {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return d1 > d2
        }).first
    }
}
