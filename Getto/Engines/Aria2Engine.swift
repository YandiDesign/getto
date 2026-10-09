import Foundation

/// Mesin HTTP/FTP/BitTorrent via satu binary `aria2c` yang dikendalikan JSON-RPC.
/// Alasan pilih aria2c: satu binary menangani multi-koneksi HTTP + torrent/magnet,
/// tanpa wrapper C++ (lihat rencana). aria2c dijalankan dengan --enable-rpc pada
/// port loopback acak + secret acak per sesi.
final class Aria2Engine: DownloadEngine {
    private var rpcPort: Int = 0
    private var rpcSecret: String = ""
    private var daemon: Process?
    private let session = URLSession.shared

    var isRunning: Bool { daemon?.isRunning ?? false }

    // MARK: - Daemon lifecycle

    func ensureRunning(settings: AppSettings) async throws {
        if isRunning { return }
        guard let aria2 = EngineProcessManager.shared.binaryPath(named: "aria2c") else {
            throw EngineError.binaryNotFound("aria2c")
        }
        rpcPort = 6800 + Int.random(in: 0..<2000)
        rpcSecret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let sessionDir = supportDir()
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let args = [
            "--enable-rpc",
            "--rpc-listen-all=false",
            "--rpc-listen-port=\(rpcPort)",
            "--rpc-secret=\(rpcSecret)",
            "--dir=\(sessionDir.path)",
            "--continue=true",
            "--max-concurrent-downloads=\(max(1, settings.maxConcurrentDownloads))",
            "--split=\(max(1, min(16, settings.segmentsPerDownload)))",
            "--max-connection-per-server=\(max(1, min(16, settings.segmentsPerDownload)))",
            "--min-split-size=1M",
            "--enable-dht=\(settings.torrentDHT ? "true" : "false")",
            "--enable-peer-exchange=\(settings.torrentPEX ? "true" : "false")",
            "--bt-force-encryption=\(settings.torrentEncryption ? "true" : "false")",
            "--listen-port=\(settings.torrentPort)",
            "--seed-ratio=\(settings.torrentSeedRatioLimit)",
            "--max-overall-download-limit=\(settings.globalSpeedLimitKBps > 0 ? "\(settings.globalSpeedLimitKBps)K" : "0")",
            "--max-overall-upload-limit=\(settings.torrentUploadLimitKBps > 0 ? "\(settings.torrentUploadLimitKBps)K" : "0")",
            "--daemon=false",
            "--quiet=true"
        ]
        daemon = try EngineProcessManager.shared.launch(executable: aria2, arguments: args, onLine: { line in
            Logger.log("aria2: \(line)")
        })
        // Tunggu RPC siap (poll getVersion, maks ~5 dtk)
        for _ in 0..<25 {
            do { _ = try await rpc(method: "aria2.getVersion", params: []); return }
            catch { try await Task.sleep(nanoseconds: 200_000_000) }
        }
        throw EngineError.launchFailed("aria2c tidak merespons JSON-RPC.")
    }

    func shutdown() {
        daemon?.terminate()
        daemon = nil
    }

    private func supportDir() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Getto/downloads", isDirectory: true)
    }

    // MARK: - DownloadEngine

    func add(urlString: String, fileName: String, destinationDirectory: String, segments: Int, headers: [String: String] = [:]) async throws -> String {
        guard URL(string: urlString) != nil else { throw EngineError.invalidURL }
        let safe = DownloadItem.sanitizedFileName(fileName)
        var options: [String: Any] = [
            "dir": destinationDirectory,
            "out": safe,
            "split": "\(max(1, min(16, segments)))",
            "max-connection-per-server": "\(max(1, min(16, segments)))",
            "continue": "true"
        ]
        // Header kustom per unduhan (Cookie/Referer browser, auth).
        // Format aria2: array "Nama: nilai".
        let headerLines = headers
            .filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "\($0.key.trimmingCharacters(in: .whitespaces)): \($0.value)" }
        if !headerLines.isEmpty {
            options["header"] = headerLines
        }
        let params: [Any] = [[urlString], options]
        let result = try await rpc(method: "aria2.addUri", params: params)
        guard let gid = result as? String else { throw EngineError.rpcFailed("addUri tanpa gid") }
        return gid
    }

    /// Tambah torrent dari file .torrent lokal (base64) atau magnet link.
    func addTorrent(source: TorrentSource, destinationDirectory: String, selectedIndexes: [Int]? = nil) async throws -> String {
        var options: [String: Any] = ["dir": destinationDirectory]
        if let idx = selectedIndexes, !idx.isEmpty {
            options["select-file"] = idx.map(String.init).joined(separator: ",")
        }
        let params: [Any]
        switch source {
        case .magnet(let uri):
            params = [[uri], options]
            let result = try await rpc(method: "aria2.addUri", params: params)
            guard let gid = result as? String else { throw EngineError.rpcFailed("addUri magnet tanpa gid") }
            return gid
        case .torrentFile(let url):
            let data = try Data(contentsOf: url)
            params = [data.base64EncodedString(), [] as [String], options]
            let result = try await rpc(method: "aria2.addTorrent", params: params)
            guard let gid = result as? String else { throw EngineError.rpcFailed("addTorrent tanpa gid") }
            return gid
        }
    }

    func pause(engineId: String) async throws {
        _ = try await rpc(method: "aria2.pause", params: [engineId])
    }

    func resume(engineId: String) async throws {
        _ = try await rpc(method: "aria2.unpause", params: [engineId])
    }

    func cancel(engineId: String) async throws {
        _ = try await rpc(method: "aria2.remove", params: [engineId])
    }

    func status(engineId: String) async throws -> EngineStatus? {
        let result = try await rpc(method: "aria2.tellStatus", params: [engineId, ["gid", "status", "totalLength", "completedLength", "downloadSpeed", "uploadSpeed", "eta", "numSeeders", "connections", "errorMessage", "bittorrent"]])
        guard let dict = result as? [String: Any] else { return nil }
        let total = Int64(dict["totalLength"] as? String ?? "0") ?? 0
        let done = Int64(dict["completedLength"] as? String ?? "0") ?? 0
        let speed = Int64(dict["downloadSpeed"] as? String ?? "0") ?? 0
        let up = Int64(dict["uploadSpeed"] as? String ?? "0") ?? 0
        let etaRaw = dict["eta"]
        let eta: Int64
        if let e = etaRaw as? String { eta = Int64(e) ?? 0 } else if let e = etaRaw as? Int { eta = Int64(e) } else { eta = 0 }
        let st = dict["status"] as? String ?? "active"
        let seeds = Int(dict["numSeeders"] as? String ?? "0") ?? 0
        let peers = Int(dict["connections"] as? String ?? "0") ?? 0
        let errMsg = dict["errorMessage"] as? String
        return EngineStatus(
            totalBytes: total, downloadedBytes: done, speedBytesPerSec: speed,
            etaSeconds: max(0, eta), numSeeds: seeds, numPeers: peers, uploadSpeed: up,
            isComplete: st == "complete",
            errorMessage: (errMsg?.isEmpty == false) ? errMsg : nil
        )
    }

    /// Daftar file dalam torrent (untuk picker): butuh gid yang sudah ditambahkan (pause dulu).
    func torrentFiles(engineId: String) async throws -> [TorrentFileEntry] {
        let result = try await rpc(method: "aria2.getFiles", params: [engineId])
        guard let arr = result as? [[String: Any]] else { return [] }
        return arr.enumerated().map { (i, f) in
            TorrentFileEntry(
                index: Int(f["index"] as? String ?? "\(i + 1)") ?? (i + 1),
                path: f["path"] as? String ?? "file-\(i)",
                length: Int64(f["length"] as? String ?? "0") ?? 0,
                selected: (f["selected"] as? String ?? "true") == "true"
            )
        }
    }

    func setSelectedFiles(engineId: String, indexes: [Int]) async throws {
        _ = try await rpc(method: "aria2.changeOption", params: [engineId, ["select-file": indexes.map(String.init).joined(separator: ",")]])
    }

    /// Ubah batas kecepatan global (0 = tanpa batas). Dipakai slow mode (1 KB/s).
    func setGlobalSpeedLimit(kbps: Int) async throws {
        _ = try await rpc(method: "aria2.changeGlobalOption", params: [["max-overall-download-limit": kbps > 0 ? "\(kbps)K" : "0"]])
    }

    // MARK: - JSON-RPC

    private func rpc(method: String, params: [Any]) async throws -> Any? {
        let url = URL(string: "http://127.0.0.1:\(rpcPort)/jsonrpc")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": UUID().uuidString,
            "method": method,
            "params": ["token:\(rpcSecret)"] + params
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, _) = try await session.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let err = json?["error"] as? [String: Any] {
                throw EngineError.rpcFailed("\(err["message"] ?? err)")
            }
            return json?["result"]
        } catch let e as EngineError {
            throw e
        } catch {
            throw EngineError.rpcFailed(error.localizedDescription)
        }
    }

    enum TorrentSource {
        case magnet(String)
        case torrentFile(URL)
    }
}
