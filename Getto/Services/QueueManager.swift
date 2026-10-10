import AppKit
import Foundation
import Combine

/// Antrean unduhan: batas konkurensi, persistensi, polling status aria2.
final class QueueManager: ObservableObject {
    static let shared = QueueManager()

    @Published private(set) var items: [DownloadItem] = []
    @Published var speedHistory: [Double] = []
    /// Slow mode: batasi semua unduhan ke 1 KB/s (pause semu).
    @Published var slowMode: Bool = false {
        didSet {
            settings.slowMode = slowMode
            applySlowMode()
        }
    }
    @Published var settings: AppSettings = .default {
        didSet {
            PersistenceStore.shared.saveSettings(settings)
            // Tepi toggle shutdown: nyalakan → evaluasi langsung (mis. semua sudah
            // selesai); matikan → batalkan jadwal tertunda.
            if !oldValue.shutdownWhenDone && settings.shutdownWhenDone {
                maybeScheduleShutdown()
            }
            if oldValue.shutdownWhenDone && !settings.shutdownWhenDone {
                cancelPendingShutdown()
            }
        }
    }

    let aria2 = Aria2Engine()
    private var pollTimer: Timer?
    private var lastProgressSave = Date.distantPast
    private var runningCount: Int { items.filter { $0.status == .downloading }.count }

    private init() {
        settings = PersistenceStore.shared.loadSettings()
        slowMode = settings.slowMode
        items = PersistenceStore.shared.loadQueue()
        // aria2 gid tidak bertahan antar sesi → reset engineId item yang belum selesai
        for i in items.indices where items[i].status != .completed {
            items[i].engineId = nil
            if items[i].status == .downloading { items[i].status = .queued }
        }
    }

    // MARK: - Lifecycle

    func start() async {
        // Server lokal untuk ekstensi: jalan terlepas dari status aria2.
        LocalHTTPServer.shared.start()
        do {
            try await aria2.ensureRunning(settings: settings)
            if slowMode { try? await aria2.setGlobalSpeedLimit(kbps: 1) }
            // Lanjutkan otomatis item yang masih queued (maks konkurensi)
            await MainActor.run { self.launchNextIfNeeded() }
            startPolling()
        } catch {
            Logger.log("aria2 start gagal: \(error)")
        }
    }

    func toggleSlowMode() {
        slowMode.toggle()
    }

    /// Terapkan batas ke aria2 yang sedang berjalan (media baru ikut via limit-rate).
    /// Media yang sedang berjalan di-restart agar limit baru berlaku realtime
    /// (yt-dlp resume .part, hanya jeda ~1-2 detik).
    private func applySlowMode() {
        Logger.log("slowMode=\(slowMode)")
        if aria2.isRunning {
            Task {
                do {
                    if self.slowMode {
                        try await self.aria2.setGlobalSpeedLimit(kbps: 1)
                    } else {
                        try await self.aria2.setGlobalSpeedLimit(kbps: self.settings.globalSpeedLimitKBps)
                    }
                } catch {
                    Logger.log("slowMode apply: \(error)")
                }
            }
        }
        for item in items where item.isMedia && item.status == .downloading {
            restartMediaForSlowMode(item)
        }
    }

    /// Hentikan proses media lama lalu luncurkan ulang dengan limit saat ini.
    /// Status tetap downloading; guard generasi di catch mengabaikan error task lama.
    private func restartMediaForSlowMode(_ item: DownloadItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }),
              items[idx].status == .downloading else { return }
        Logger.log("slowMode restart \(items[idx].fileName)")
        mediaTasks[item.id]?.cancel()
        if let proc = mediaProcesses[item.id] {
            proc.terminate()
            mediaProcesses.removeValue(forKey: item.id)
        }
        launch(items[idx])
    }

    func stop() {
        pollTimer?.invalidate()
        aria2.shutdown()
        LocalHTTPServer.shared.stop()
        EngineProcessManager.shared.terminateAll()
        PersistenceStore.shared.saveQueue(items)
    }

    // MARK: - Tambah unduhan

    /// Bangun header HTTP dari parameter scheme getto://add
    /// (cookies, referer, dan profil browser asli dari ekstensi).
    static func headersFromScheme(_ comps: URLComponents) -> [String: String] {
        var headers: [String: String] = [:]
        let items = comps.queryItems ?? []
        if let c = items.first(where: { $0.name == "cookies" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            headers["Cookie"] = c
        }
        if let r = items.first(where: { $0.name == "referer" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            headers["Referer"] = r
        }
        // Profil browser (UA + client hint) — wajib agar cookie sesi situs
        // tetap sah; tanpa ini situs menolak dengan "access denied".
        if let encoded = items.first(where: { $0.name == "h" })?.value,
           let data = Data(base64Encoded: encoded),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] {
            for (k, v) in dict where !k.isEmpty && !v.isEmpty { headers[k] = v }
        }
        return headers
    }

    /// Pecah input multi-baris menjadi item; kembalikan item yang dibuat.
    @discardableResult
    func addLinks(_ rawText: String, headers: [String: String] = [:]) -> [DownloadItem] {
        cancelPendingShutdown()
        let urls = rawText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { ClipboardService.isDownloadableURL($0) }
        var created: [DownloadItem] = []
        for url in urls {
            // Normalisasi Google Drive → link download langsung (hindari
            // halaman konfirmasi virus-scan untuk file besar).
            let normalized = googleDriveDirectURL(url) ?? url
            // Jangan duplikat URL yang masih aktif (queued/downloading) — cukup kembalikan item lama.
            if let existing = items.first(where: { $0.urlString == normalized && ($0.status == .queued || $0.status == .downloading) }) {
                created.append(existing)
                continue
            }
            if normalized.lowercased().hasPrefix("magnet:?") {
                created.append(addMagnet(normalized))
            } else if ClipboardService.isVideoURL(normalized) {
                created.append(addMediaPlaceholder(url: normalized, headers: headers))
            } else {
                created.append(addHTTP(url: normalized, headers: headers))
            }
        }
        save()
        launchNextIfNeeded()
        return created
    }

    private func resolvedDestination(fileName: String) -> (dir: String, finalName: String) {
        let dir = settings.downloadDirectory
        var name = DownloadItem.sanitizedFileName(fileName)
        let fm = FileManager.default
        switch settings.duplicateBehavior {
        case "skip":
            if fm.fileExists(atPath: (dir as NSString).appendingPathComponent(name)) { return (dir, name) }
        case "overwrite":
            break
        default: // rename
            var candidate = name
            var n = 1
            while fm.fileExists(atPath: (dir as NSString).appendingPathComponent(candidate)) {
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
                n += 1
            }
            name = candidate
        }
        return (dir, name)
    }

    func addHTTP(url: String, headers: [String: String] = [:]) -> DownloadItem {
        var name = DownloadItem.fileNameFrom(urlString: url)
        let (dir, final) = resolvedDestination(fileName: name)
        name = final
        var item = DownloadItem(urlString: url, fileName: name, destinationPath: (dir as NSString).appendingPathComponent(name), kind: .http)
        item.headers = headers
        items.insert(item, at: 0)
        // Probe metadata sekali (single flight): update UI cepat + dipakai
        // ulang saat launch agar nama `out` aria2 selalu benar.
        let itemId = item.id
        let itemHeaders = headers
        probeTasks[itemId] = Task { () -> ProbeInfo in
            let info = await self.probeHEADInfo(urlString: url, headers: itemHeaders)
            await MainActor.run {
                // Update UI saja (rename hanya selagi queued/belum jalan).
                if let idx = self.items.firstIndex(where: { $0.id == itemId }),
                   self.items[idx].status == .queued {
                    self.applyProbeInfo(info, to: itemId, allowRename: true)
                }
            }
            return info
        }
        return item
    }

    func addMediaPlaceholder(url: String, headers: [String: String] = [:]) -> DownloadItem {
        let name = DownloadItem.sanitizedFileName(DownloadItem.fileNameFrom(urlString: url))
        let (dir, final) = resolvedDestination(fileName: name + ".mp4")
        var item = DownloadItem(urlString: url, fileName: final, destinationPath: (dir as NSString).appendingPathComponent(final), kind: .video)
        item.headers = headers
        items.insert(item, at: 0)
        return item
    }

    /// Ganti nama placeholder media dengan judul asli dari pratinjau yt-dlp.
    func applyMediaTitle(id: UUID, title: String, ext: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var name = DownloadItem.sanitizedFileName(title)
        if (name as NSString).pathExtension.lowercased() != ext.lowercased() {
            name += "." + ext.lowercased()
        }
        let dir = (items[idx].destinationPath as NSString).deletingLastPathComponent
        var candidate = name
        var n = 1
        let fm = FileManager.default
        while fm.fileExists(atPath: (dir as NSString).appendingPathComponent(candidate)) {
            let base = (name as NSString).deletingPathExtension
            candidate = "\(base) (\(n)).\(ext.lowercased())"
            n += 1
        }
        items[idx].fileName = candidate
        items[idx].destinationPath = (dir as NSString).appendingPathComponent(candidate)
        save()
    }

    func addMagnet(_ uri: String) -> DownloadItem {
        let name = DownloadItem.sanitizedFileName("magnet-\(String(uri.suffix(12)))")
        let (dir, final) = resolvedDestination(fileName: name)
        var item = DownloadItem(urlString: uri, fileName: final, destinationPath: (dir as NSString).appendingPathComponent(final), kind: .torrent)
        item.status = .queued
        items.insert(item, at: 0)
        return item
    }

    func addTorrentFile(_ fileURL: URL, selectedIndexes: [Int]? = nil) {
        cancelPendingShutdown()
        let name = fileURL.deletingPathExtension().lastPathComponent
        let (dir, final) = resolvedDestination(fileName: name)
        var item = DownloadItem(urlString: fileURL.absoluteString, fileName: final,
                                destinationPath: (dir as NSString).appendingPathComponent(final), kind: .torrent)
        item.status = .queued
        items.insert(item, at: 0)
        // Simpan pilihan file sebagai phaseDescription sementara "torrent:<indexes>"
        if let idx = selectedIndexes {
            item.phaseDescription = "select:" + idx.map(String.init).joined(separator: ",")
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
        }
        save()
        launchNextIfNeeded()
    }

    /// Hasil probe metadata (nama server + ukuran). Satu flight per item.
    private struct ProbeInfo {
        var fileName: String?
        var totalBytes: Int64 = 0
    }
    private var probeTasks: [UUID: Task<ProbeInfo, Never>] = [:]

    /// Parse Content-Disposition → nama file (dukung RFC 5987 filename*).
    /// Murni (bisa diuji).
    static func filenameFromContentDisposition(_ cd: String) -> String? {
        // filename*=UTF-8''nama%20file.mp4
        if let star = cd.range(of: "filename*=") {
            var v = String(cd[star.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let q = v.first, q == "\"" || q == "'" {
                v = String(v.dropFirst().prefix(while: { $0 != q }))
            } else {
                v = v.split(separator: ";").first.map(String.init) ?? v
            }
            if let utf = v.range(of: "UTF-8''", options: .caseInsensitive) {
                v = String(v[utf.upperBound...])
            }
            let clean = DownloadItem.sanitizedFileName(
                (v.removingPercentEncoding ?? v).trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")))
            if !clean.isEmpty { return clean }
        }
        if let r = cd.range(of: "filename=") {
            var v = String(cd[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let q = v.first, q == "\"" || q == "'" {
                v = String(v.dropFirst().prefix(while: { $0 != q }))
            } else {
                v = v.split(separator: ";").first.map(String.init) ?? v
            }
            let clean = DownloadItem.sanitizedFileName(
                (v.removingPercentEncoding ?? v).trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")))
            if !clean.isEmpty { return clean }
        }
        return nil
    }

    /// HEAD metadata (nama + ukuran). Bila HEAD tak memberi nama file
    /// (mis. Google Drive), coba GET 1 byte dan baca header responsnya.
    /// Gagal → info kosong (lanjut tanpa metadata).
    private func probeHEADInfo(urlString: String, headers: [String: String]) async -> ProbeInfo {
        guard let url = URL(string: urlString) else { return ProbeInfo() }
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 10
        for (k, v) in headers { head.setValue(v, forHTTPHeaderField: k) }
        do {
            let (_, resp) = try await URLSession.shared.data(for: head)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return ProbeInfo()
            }
            let info = probeInfoFromHeaders(http, fallbackURL: urlString)
            if info.fileName != nil || info.totalBytes > 0 {
                return info
            }
        } catch { /* lanjut ke fallback GET */ }
        // Fallback: GET 1 byte pertama — hanya header responsnya yang dibaca,
        // bodi tidak pernah di-buffer (aman untuk file besar).
        var get = URLRequest(url: url)
        get.httpMethod = "GET"
        get.timeoutInterval = 10
        get.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        for (k, v) in headers { get.setValue(v, forHTTPHeaderField: k) }
        do {
            let (_, resp) = try await URLSession.shared.bytes(for: get)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return ProbeInfo()
            }
            return probeInfoFromHeaders(http, fallbackURL: urlString)
        } catch {
            return ProbeInfo()
        }
    }

    private func probeInfoFromHeaders(_ http: HTTPURLResponse, fallbackURL: String) -> ProbeInfo {
        var total: Int64 = 0
        if let len = http.value(forHTTPHeaderField: "Content-Length"), let n = Int64(len), n > 0 {
            total = n
        } else if let cr = http.value(forHTTPHeaderField: "Content-Range"),
                  let slash = cr.split(separator: "/").last, let n = Int64(slash), n > 0 {
            total = n // "bytes 0-0/12345" → 12345
        }
        var name: String? = nil
        if let cd = http.value(forHTTPHeaderField: "Content-Disposition") {
            name = QueueManager.filenameFromContentDisposition(cd)
        }
        return ProbeInfo(fileName: name, totalBytes: total)
    }

    /// Terapkan hasil probe ke item (rename hanya sebelum diluncurkan agar
    /// tidak bentrok dengan `out` aria2 yang sudah jalan).
    private func applyProbeInfo(_ info: ProbeInfo, to id: UUID, allowRename: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var changed = false
        if allowRename, let name = info.fileName, !name.isEmpty, items[idx].fileName != name {
            let (dir, final) = resolvedDestination(fileName: name)
            items[idx].fileName = final
            items[idx].destinationPath = (dir as NSString).appendingPathComponent(final)
            changed = true
        }
        if info.totalBytes > 0, items[idx].totalBytes != info.totalBytes {
            items[idx].totalBytes = info.totalBytes
            changed = true
        }
        if changed { save() }
    }

    // MARK: - Kontrol

    /// Proses yt-dlp yang sedang berjalan per item + Task peluncurnya,
    /// agar pause/cancel media benar-benar menghentikan unduhan.
    private var mediaProcesses: [UUID: Process] = [:]
    private var mediaTasks: [UUID: Task<Void, Never>] = [:]
    /// Generasi peluncuran per item: catch dari task lama yang sudah digantikan
    /// relaunch (mis. restart slow mode) harus diabaikan.
    private var mediaGen: [UUID: Int] = [:]
    /// Hitung gagal RPC beruntun per gid (untuk self-heal gid basi).
    private var rpcFailCount: [String: Int] = [:]
    /// Item yang sudah diverifikasi Cloudflare (satu kali per item).
    private var cfProbed: Set<UUID> = []

    func pause(_ item: DownloadItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        // Media (yt-dlp): tandai task dibatalkan lalu matikan prosesnya.
        // Handler terminasi akan resume-kontinuasi sehingga Task selesai dan
        // blok catch di launch() mengubah status jadi paused (tanpa error).
        if item.isMedia {
            mediaTasks[items[idx].id]?.cancel()
            if let proc = mediaProcesses[items[idx].id] {
                proc.terminate()
                mediaProcesses.removeValue(forKey: items[idx].id)
            }
            items[idx].status = .paused
            items[idx].speedBytesPerSec = 0
            save()
            return
        }
        items[idx].status = .paused
        if let gid = items[idx].engineId {
            Task {
                do { try await self.aria2.pause(engineId: gid) }
                catch { Logger.log("pause \(gid): \(error)") }
            }
        }
        save()
    }

    func resume(_ item: DownloadItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        // aria2 yang masih punya gid hidup: lanjutkan langsung tanpa antre ulang.
        if !items[idx].isMedia, let gid = items[idx].engineId,
           items[idx].status == .paused || items[idx].status == .failed {
            items[idx].status = .downloading
            items[idx].errorMessage = nil
            save()
            Task {
                do { try await self.aria2.resume(engineId: gid) }
                catch {
                    Logger.log("resume \(gid): \(error)")
                    await MainActor.run { self.requeue(item.id) }
                }
            }
            return
        }
        requeue(items[idx].id)
    }

    /// Kembalikan item ke antrean untuk diluncurkan ulang.
    private func requeue(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        cancelPendingShutdown()
        items[idx].status = .queued
        items[idx].errorMessage = nil
        save()
        launchNextIfNeeded()
    }

    func cancel(_ item: DownloadItem, deleteFile: Bool = false) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        probeTasks.removeValue(forKey: items[idx].id)
        // Hentikan juga proses media yang masih hidup (sebelumnya bocor).
        mediaTasks[items[idx].id]?.cancel()
        mediaTasks.removeValue(forKey: items[idx].id)
        mediaGen.removeValue(forKey: items[idx].id)
        if let proc = mediaProcesses[items[idx].id] {
            proc.terminate()
            mediaProcesses.removeValue(forKey: items[idx].id)
        }
        if let gid = items[idx].engineId {
            Task { try? await self.aria2.cancel(engineId: gid) }
        }
        if deleteFile {
            try? FileManager.default.removeItem(atPath: items[idx].destinationPath)
        }
        items.remove(at: idx)
        save()
        launchNextIfNeeded()
    }

    func retry(_ item: DownloadItem) { resume(item) }

    func pauseAll() { items.filter { $0.status == .downloading || $0.status == .queued }.forEach { pause($0) } }
    func resumeAll() { items.filter { $0.status == .paused || $0.status == .failed }.forEach { resume($0) } }
    func clearCompleted() {
        items.removeAll { $0.status == .completed }
        save()
    }

    // MARK: - Scheduler

    private func launchNextIfNeeded() {
        guard aria2.isRunning else {
            Task { await start() }
            return
        }
        let maxC = max(1, settings.maxConcurrentDownloads)
        while runningCount < maxC {
            guard let idx = items.firstIndex(where: { $0.status == .queued }) else { break }
            launch(items[idx])
        }
    }

    private func launch(_ item: DownloadItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].status = .downloading
        items[idx].errorMessage = nil
        mediaTasks[item.id]?.cancel()
        mediaGen[item.id, default: 0] += 1
        let gen = mediaGen[item.id]!
        mediaTasks[item.id] = Task {
            do {
                if item.kind == .torrent {
                    try await launchTorrent(item: item)
                } else if item.kind == .video || item.kind == .audio {
                    try await launchMedia(item: item)
                } else {
                    try await launchHTTP(item: item)
                }
            } catch {
                // Gagal 403 pada link HTTP biasa: verifikasi dulu apakah ini
                // tantangan Cloudflare agar pesannya spesifik (bukan sekadar login).
                var friendly = friendlyErrorMessage(error.localizedDescription)
                if item.kind == .http && looksLikeAccessDenied(error.localizedDescription),
                   await self.probeCloudflare(item: item) {
                    friendly = NSLocalizedString("err.cloudflare", value: "Situs memverifikasi browser (Cloudflare). Buka link di browser sampai verifikasi selesai, lalu BATAL unduhan di browser (cookie tetap tersimpan) dan kirim ulang dari sini — cookie & User-Agent terbaru ikut terbawa.", comment: "")
                }
                let finalMessage = friendly
                await MainActor.run {
                    guard let j = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                    // Task lama yang sudah digantikan relaunch (restart slow mode /
                    // pause-resume cepat): abaikan agar tidak menimpa status baru.
                    guard self.mediaGen[item.id] == gen else { return }
                    // Dibatalkan via pause/cancel: jadikan paused diam-diam, bukan gagal.
                    if Task.isCancelled || self.mediaTasks[item.id]?.isCancelled == true {
                        self.items[j].status = .paused
                        self.items[j].speedBytesPerSec = 0
                        self.save()
                        return
                    }
                    self.items[j].status = .failed
                    self.items[j].errorMessage = finalMessage
                    NotificationService.shared.notifyFailed(fileName: self.items[j].fileName, reason: self.items[j].errorMessage ?? "")
                    self.save()
                    self.launchNextIfNeeded()
                }
            }
            if mediaGen[item.id] == gen { mediaTasks.removeValue(forKey: item.id) }
        }
    }

    /// UA browser desktop: banyak CDN menolak UA bot generik (aria2/...).
    static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    /// Gabung header item dengan default Pengaturan → Jaringan
    /// (item menang bila kunci sama).
    private func effectiveHeaders(for item: DownloadItem) -> [String: String] {
        var h = item.headers
        if !h.keys.contains(where: { $0.lowercased() == "user-agent" }) {
            h["User-Agent"] = QueueManager.defaultUserAgent
        }
        let sc = settings.cookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sc.isEmpty {
            h["Cookie"] = [h["Cookie"], sc].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "; ")
        }
        if !settings.httpUsername.isEmpty, h["Authorization"] == nil {
            let cred = Data("\(settings.httpUsername):\(settings.httpPassword)".utf8).base64EncodedString()
            h["Authorization"] = "Basic \(cred)"
        }
        for (k, v) in settings.customHeaders where h[k] == nil { h[k] = v }
        return h
    }

    private func launchHTTP(item: DownloadItem) async throws {
        try await aria2.ensureRunning(settings: settings)
        // Tunggu probe (single flight, instan bila sudah selesai) lalu pakai
        // nama/ukuran final agar `out` aria2 tepat (mis. nama asli GDrive).
        if let probe = probeTasks[item.id] {
            let info = await probe.value
            await MainActor.run {
                self.applyProbeInfo(info, to: item.id, allowRename: true)
                self.probeTasks.removeValue(forKey: item.id)
            }
        }
        guard let fresh = await MainActor.run(body: { self.items.first(where: { $0.id == item.id }) }) else {
            await MainActor.run { self.probeTasks.removeValue(forKey: item.id) }
            return
        }
        let gid = try await aria2.add(
            urlString: fresh.urlString,
            fileName: (fresh.destinationPath as NSString).lastPathComponent,
            destinationDirectory: (fresh.destinationPath as NSString).deletingLastPathComponent,
            segments: settings.segmentsPerDownload,
            headers: effectiveHeaders(for: fresh)
        )
        await MainActor.run {
            if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[idx].engineId = gid
                self.save()
            }
        }
    }

    private func launchTorrent(item: DownloadItem) async throws {
        try await aria2.ensureRunning(settings: settings)
        var selected: [Int]? = nil
        if let phase = item.phaseDescription, phase.hasPrefix("select:") {
            selected = phase.dropFirst(7).split(separator: ",").compactMap { Int($0) }
        }
        let gid: String
        if item.urlString.lowercased().hasPrefix("magnet:") {
            gid = try await aria2.addTorrent(source: .magnet(item.urlString),
                                            destinationDirectory: (item.destinationPath as NSString).deletingLastPathComponent,
                                            selectedIndexes: selected)
        } else if let fileURL = URL(string: item.urlString), fileURL.isFileURL {
            gid = try await aria2.addTorrent(source: .torrentFile(fileURL),
                                            destinationDirectory: (item.destinationPath as NSString).deletingLastPathComponent,
                                            selectedIndexes: selected)
        } else {
            // URL .torrent jarak jauh: unduh dulu file-nya lalu addTorrent
            let (tmp, _) = try await URLSession.shared.download(from: URL(string: item.urlString)!)
            gid = try await aria2.addTorrent(source: .torrentFile(tmp),
                                            destinationDirectory: (item.destinationPath as NSString).deletingLastPathComponent,
                                            selectedIndexes: selected)
        }
        await MainActor.run {
            if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[idx].engineId = gid
                self.save()
            }
        }
    }

    private func launchMedia(item: DownloadItem) async throws {
        var opts = MediaOptions()
        opts.quality = settings.defaultQuality
        opts.container = settings.defaultContainer
        opts.videoCodec = settings.defaultVideoCodec
        opts.audioFormat = settings.defaultAudioFormat
        opts.audioOnly = settings.defaultAudioOnly
        opts.embedSubtitle = settings.defaultEmbedSubtitle
        let dir = (item.destinationPath as NSString).deletingLastPathComponent
        defer { mediaProcesses.removeValue(forKey: item.id) }
        let file = try await MediaEngine.shared.download(
            urlString: item.urlString, options: opts, destinationDirectory: dir,
            subtitleLangs: settings.defaultSubtitleLangs,
            limitRateKBps: slowMode ? 1 : nil,
            headers: effectiveHeaders(for: item),
            cookiesFromBrowser: settings.cookiesFromBrowser,
            processHandler: { [weak self] proc in self?.mediaProcesses[item.id] = proc }
        ) { [weak self] downloaded, total, speed, phase in
            guard let strongSelf = self else { return }
            DispatchQueue.main.async {
                guard let idx = strongSelf.items.firstIndex(where: { $0.id == item.id }) else { return }
                strongSelf.items[idx].totalBytes = total
                strongSelf.items[idx].downloadedBytes = downloaded
                strongSelf.items[idx].speedBytesPerSec = speed
                strongSelf.items[idx].phaseDescription = phase
                if total > 0 && speed > 0 {
                    let remain = max(0, total - downloaded)
                    strongSelf.items[idx].etaSeconds = remain / speed
                }
                // Simpan berkala agar progres video tidak hilang bila app ditutup
                if Date().timeIntervalSince(strongSelf.lastProgressSave) > 2 {
                    strongSelf.lastProgressSave = Date()
                    strongSelf.recordSpeedSample()
                    strongSelf.save()
                }
            }
        }
        await MainActor.run {
            guard let idx = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[idx].status = .completed
            self.items[idx].completedAt = Date()
            self.items[idx].destinationPath = file.path
            self.items[idx].fileName = file.lastPathComponent
            NotificationService.shared.notifyCompleted(fileName: self.items[idx].fileName, fileURL: file)
            self.save()
            self.maybeScheduleShutdown()
            self.launchNextIfNeeded()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        // Timer harus dijadwalkan di main runloop; start() bisa dipanggil dari thread background.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.pollOnce()
            }
        }
    }

    private func pollOnce() {
        Task {
            var changed = false
            for item in items where item.status == .downloading && item.engineId != nil && item.kind != .video && item.kind != .audio {
                do {
                    if let st = try await aria2.status(engineId: item.engineId!) {
                        self.rpcFailCount.removeValue(forKey: item.engineId!)
                        await MainActor.run {
                            guard let idx = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                            self.items[idx].totalBytes = st.totalBytes
                            self.items[idx].downloadedBytes = st.downloadedBytes
                            self.items[idx].speedBytesPerSec = st.speedBytesPerSec
                            self.items[idx].etaSeconds = st.etaSeconds
                            self.items[idx].numSeeds = st.numSeeds
                            self.items[idx].numPeers = st.numPeers
                            self.items[idx].uploadSpeed = st.uploadSpeed
                            if st.totalBytes > 0 {
                                self.items[idx].ratio = Double(st.uploadSpeed) / max(1, Double(st.speedBytesPerSec))
                            }
                            // Tunjuk hasil yang sebenarnya. Torrent magnets diberi nama
                            // sementara "magnet-xxxx"; nama asli baru diketahui
                            // setelah metadata masuk. Lewati pseudo-file metadata
                            // aria2 ("[METADATA]...").
                            if self.items[idx].isTorrent,
                               let real = st.filePaths.first(where: { !$0.hasPrefix("[METADATA]") }) {
                                let final = st.isMultiFileTorrent
                                    ? (real as NSString).deletingLastPathComponent
                                    : real
                                if final != self.items[idx].destinationPath {
                                    self.items[idx].destinationPath = final
                                    self.items[idx].fileName =
                                        DownloadItem.sanitizedFileName((final as NSString).lastPathComponent)
                                }
                            }
                            // Magnet: aria2 lebih dulu mengunduh metadata
                            // (.torrent) dan melaporkan unduhan itu `complete`,
                            // lalu MEMINDAHKAN isi ke gid baru. Tanpa ini item
                            // ditandai selesai pada ukuran metadata dan unduhan
                            // isi yang sebenarnya jadi tidak pernah dilacak.
                            if let next = st.followsGid {
                                self.items[idx].engineId = next
                                self.rpcFailCount.removeValue(forKey: next)
                                self.items[idx].phaseDescription = nil
                            } else if self.items[idx].isTorrent,
                                      !st.isComplete,
                                      st.totalBytes == 0,
                                      self.items[idx].status == .downloading {
                                // Magnet belum dapat metadata: total masih 0, jadi
                                // progres akan 0% — beri tahu agar tidak terlihat
                                // macet tanpa sebab.
                                self.items[idx].phaseDescription = NSLocalizedString(
                                    "torrent.metadata",
                                    value: "Mengambil metadata torrent…",
                                    comment: "")
                            } else if st.isComplete {
                                let donePath = self.items[idx].destinationPath
                                let doneName = self.items[idx].fileName
                                if !self.items[idx].isMedia && QueueManager.isHTMLInterstitial(path: donePath, fileName: doneName) {
                                    // Server mengembalikan halaman (login/konfirmasi/
                                    // verifikasi), bukan file — hapus sampahnya,
                                    // tandai gagal dengan penyebab yang tepat.
                                    let isCF = QueueManager.savedFileIsCloudflareChallenge(path: donePath)
                                    try? FileManager.default.removeItem(atPath: donePath)
                                    self.items[idx].status = .failed
                                    self.items[idx].errorMessage = isCF
                                        ? NSLocalizedString("err.cloudflare", value: "Situs memverifikasi browser (Cloudflare). Buka link di browser sampai verifikasi selesai, lalu BATAL unduhan di browser (cookie tetap tersimpan) dan kirim ulang dari sini — cookie & User-Agent terbaru ikut terbawa.", comment: "")
                                        : NSLocalizedString("err.interstitial", value: "Server mengembalikan halaman web, bukan file (kemungkinan butuh login/konfirmasi). Coba kirim ulang dari browser yang sudah login.", comment: "")
                                    NotificationService.shared.notifyFailed(fileName: doneName, reason: self.items[idx].errorMessage ?? "")
                                } else {
                                    self.items[idx].status = .completed
                                    self.items[idx].completedAt = Date()
                                    NotificationService.shared.notifyCompleted(
                                        fileName: self.items[idx].fileName,
                                        fileURL: URL(fileURLWithPath: self.items[idx].destinationPath))
                                }
                            } else if let err = st.errorMessage {
                                self.items[idx].status = .failed
                                self.items[idx].errorMessage = friendlyErrorMessage(err)
                                NotificationService.shared.notifyFailed(fileName: self.items[idx].fileName, reason: self.items[idx].errorMessage ?? "")
                                // Penolakan akses (403/401/…) bisa berupa tantangan
                                // Cloudflare — verifikasi sekali per item lalu
                                // ganti pesannya dengan langkah yang konkret.
                                if self.items[idx].kind == .http,
                                   !self.cfProbed.contains(item.id),
                                   looksLikeAccessDenied(err) {
                                    self.cfProbed.insert(item.id)
                                    let failedID = item.id
                                    Task { [weak self] in
                                        guard let self = self,
                                              await self.probeCloudflare(item: item) else { return }
                                        await MainActor.run {
                                            guard let j = self.items.firstIndex(where: { $0.id == failedID }),
                                                  self.items[j].status == .failed else { return }
                                            self.items[j].errorMessage = NSLocalizedString("err.cloudflare", value: "Situs memverifikasi browser (Cloudflare). Buka link di browser sampai verifikasi selesai, lalu BATAL unduhan di browser (cookie tetap tersimpan) dan kirim ulang dari sini — cookie & User-Agent terbaru ikut terbawa.", comment: "")
                                            self.save()
                                        }
                                    }
                                }
                            }
                        }
                        changed = true
                    }
                } catch {
                    Logger.log("poll \(item.fileName): \(error)")
                    // Gid basi (mis. aria2 restart): beri kesempatan 10x gagal (~5 dtk),
                    // lalu antre ulang agar diunduh fresh.
                    if let gid = item.engineId {
                        let n = (self.rpcFailCount[gid] ?? 0) + 1
                        self.rpcFailCount[gid] = n
                        if n > 10 {
                            self.rpcFailCount.removeValue(forKey: gid)
                            await MainActor.run {
                                guard let idx = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                                self.items[idx].engineId = nil
                                self.requeue(item.id)
                            }
                        }
                    }
                }
            }
            if changed {
                await MainActor.run {
                    self.save()
                    self.launchNextIfNeeded()
                    self.updateDockBadge()
                    self.recordSpeedSample()
                    self.maybeScheduleShutdown()
                }
            }
        }
    }

    /// Shutdown tertunda (dijadwalkan saat semua selesai, batal bila ada unduhan baru).
    private var shutdownTask: Task<Void, Never>?

    /// Syarat shutdown: ada item dan semuanya sudah selesai/gagal (tak ada yang
    /// berjalan, antre, atau dijeda — jeda berarti pengguna ingin lanjut nanti).
    static func shouldShutdown(items: [DownloadItem]) -> Bool {
        guard !items.isEmpty else { return false }
        return items.allSatisfy { $0.status == .completed || $0.status == .failed }
    }

    /// Jadwalkan matikan komputer 60 detik lagi bila syarat terpenuhi.
    /// Idempoten: hanya satu jadwal aktif. Batal otomatis via cancelPendingShutdown().
    func maybeScheduleShutdown() {
        guard settings.shutdownWhenDone, shutdownTask == nil else { return }
        guard QueueManager.shouldShutdown(items: items) else { return }
        Logger.log("shutdown terjadwal 60 dtk")
        NotificationService.shared.notifyShutdownCountdown()
        shutdownTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.executeShutdown() }
        }
    }

    func cancelPendingShutdown() {
        if shutdownTask != nil {
            Logger.log("shutdown dibatalkan (ada aktivitas baru)")
        }
        shutdownTask?.cancel()
        shutdownTask = nil
    }

    private func executeShutdown() {
        shutdownTask = nil
        guard settings.shutdownWhenDone,
              QueueManager.shouldShutdown(items: items) else { return }
        Logger.log("shutdown dieksekusi")
        do {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", "tell application \"System Events\" to shut down"]
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                NotificationService.shared.notifyShutdownFailed()
            }
        } catch {
            Logger.log("shutdown gagal: \(error)")
            NotificationService.shared.notifyShutdownFailed()
        }
    }
    /// Verifikasi tantangan Cloudflare ("Just a moment...") untuk link HTTP
    /// yang gagal 403. Hanya dibaca maks 8KB lalu berhenti (aman memori).
    private func probeCloudflare(item: DownloadItem) async -> Bool {
        guard let url = URL(string: item.urlString) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("bytes=0-8191", forHTTPHeaderField: "Range")
        for (k, v) in effectiveHeaders(for: item) { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 15
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            guard let http = resp as? HTTPURLResponse,
                  (http.statusCode == 403 || http.statusCode == 503) else { return false }
            var data = Data()
            var count = 0
            for try await byte in bytes {
                data.append(byte)
                count += 1
                if count >= 8192 { break }
            }
            let snippet = String(data: data, encoding: .utf8) ?? ""
            return isCloudflareChallenge(statusCode: http.statusCode, bodySnippet: snippet)
        } catch {
            return false
        }
    }

    /// Validasi pasca-unduh: tolak halaman HTML yang menyamar jadi file
    /// (halaman login/konfirmasi/Cloudflare yang lolos — bukan file asli).
    /// Murni-sebagian (bisa diuji via file fixture): true = file sampah.
    static func isHTMLInterstitial(path: String, fileName: String) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        let data = fh.readData(ofLength: 2048)
        guard !data.isEmpty else { return false }
        let head = String(data: data, encoding: .utf8)?.lowercased() ?? ""
        let isHTML = head.contains("<!doctype html") || head.contains("<html")
        guard isHTML else { return false }
        // HTML wajar hanya bila memang mengunduh dokumen web.
        let ext = (fileName as NSString).pathExtension.lowercased()
        return !["html", "htm", "xhtml", "shtml", "txt", "xml", "json"].contains(ext)
    }

    /// Halaman verifikasi Cloudflare (JS challenge) yang tersimpan sebagai
    /// "file" hasil unduhan. Penyebab paling umum "access denied" walau cookie
    /// benar: `cf_clearance` basi atau User-Agent tidak sama dengan browser
    /// yang menerbitkannya.
    static func savedFileIsCloudflareChallenge(path: String) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        let data = fh.readData(ofLength: 8192)
        guard !data.isEmpty else { return false }
        let head = String(data: data, encoding: .utf8)?.lowercased() ?? ""
        let markers = ["__cf_chl", "cf-browser-verification", "just a moment",
                       "challenges.cloudflare.com", "cf-chl-", "cloudflare ray id"]
        return markers.contains { head.contains($0) }
    }

    func recordSpeedSample() {
        let total = items
            .filter { $0.status == .downloading }
            .reduce(Int64(0)) { $0 + $1.speedBytesPerSec }
        speedHistory.append(Double(total))
        if speedHistory.count > 60 { speedHistory.removeFirst(speedHistory.count - 60) }
    }

    private func updateDockBadge() {
        let active = items.filter { $0.status == .downloading }.count
        NSApp.dockTile.badgeLabel = active > 0 ? "\(active)" : nil
    }

    private func save() {
        PersistenceStore.shared.saveQueue(items)
    }
}
