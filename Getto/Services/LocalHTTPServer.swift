import AppKit
import Foundation
import Network

/// Server HTTP lokal (127.0.0.1) sebagai jalur komunikasi ekstensi → aplikasi
/// yang tidak bergantung pada Native Messaging (yang absen di sebagian
/// environment Chromium) dan tidak memicu dialog "open with" seperti URL scheme.
///
/// - POST /add        {url, cookies?, referer?} → tambah unduhan (ada headers)
/// - POST /open-sheet {} → buka sheet Tambah Unduhan
/// - GET  /ping       → {ok, version}
///
/// Keamanan: hanya listen di loopback. Request dengan header Origin
/// `chrome-extension://` harus cocok dengan ID ekstensi tersimpan;
/// tanpa Origin (curl lokal) diizinkan; Origin web asing ditolak.
final class LocalHTTPServer {
    static let shared = LocalHTTPServer()
    static let port: UInt16 = 17842

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.getto.app.localhttp")

    private init() {}

    var isRunning: Bool { listener != nil }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    Logger.log("localhttp gagal: \(err)")
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            Logger.log("localhttp jalan di 127.0.0.1:\(Self.port)")
        } catch {
            Logger.log("localhttp start gagal: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Koneksi

    private func handle(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.receiveRequest(conn, buffer: Data()) }
        }
        conn.start(queue: queue)
    }

    private func receiveRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buf = buffer
            if let data = data, !data.isEmpty { buf.append(data) }
            if error != nil || buf.count > 1_048_576 {
                conn.cancel()
                return
            }
            guard let headerEnd = self.headerEnd(in: buf) else {
                if isComplete { conn.cancel(); return }
                self.receiveRequest(conn, buffer: buf)
                return
            }
            let headerData = buf[..<headerEnd]
            var body = buf[buf.index(headerEnd, offsetBy: 4)...]
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                conn.cancel()
                return
            }
            let lines = headerText.components(separatedBy: "\r\n")
            let requestLine = lines.first ?? ""
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { headers[kv[0].lowercased()] = kv[1] }
            }
            let contentLength = Int(headers["content-length"] ?? "0") ?? 0
            if body.count < contentLength {
                // Baca sisa bodi (dibatasi 1MB).
                self.receiveBody(conn, requestLine: requestLine, headers: headers, body: Data(body), remaining: min(contentLength, 1_048_576))
                return
            }
            self.dispatch(conn, requestLine: requestLine, headers: headers, body: Data(body.prefix(contentLength)))
        }
    }

    private func receiveBody(_ conn: NWConnection, requestLine: String, headers: [String: String], body: Data, remaining: Int) {
        if remaining <= 0 {
            self.dispatch(conn, requestLine: requestLine, headers: headers, body: body)
            return
        }
        conn.receive(minimumIncompleteLength: 1, maximumLength: min(65536, remaining)) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var b = body
            if let data = data, !data.isEmpty { b.append(data) }
            if error != nil {
                conn.cancel()
                return
            }
            let left = remaining - (data?.count ?? 0)
            if left > 0 && !isComplete {
                self.receiveBody(conn, requestLine: requestLine, headers: headers, body: b, remaining: left)
            } else {
                self.dispatch(conn, requestLine: requestLine, headers: headers, body: b)
            }
        }
    }

    private func headerEnd(in buf: Data) -> Data.Index? {
        let sep: [UInt8] = [13, 10, 13, 10]
        guard buf.count >= 4 else { return nil }
        for i in 0...(buf.count - 4) {
            if buf[i] == sep[0] && buf[i+1] == sep[1] && buf[i+2] == sep[2] && buf[i+3] == sep[3] {
                return buf.startIndex.advanced(by: i)
            }
        }
        return nil
    }

    // MARK: - Dispatch

    private func dispatch(_ conn: NWConnection, requestLine: String, headers: [String: String], body: Data) {
        let parts = requestLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]).uppercased() : ""
        let path = parts.count > 1 ? String(parts[1]).split(separator: "?").first.map(String.init) ?? "/" : "/"

        // Gate Origin: chrome-extension://<id> harus cocok dengan ID tersimpan.
        // Tanpa Origin (curl lokal) diizinkan; Origin web asing ditolak.
        if let origin = headers["origin"], origin.hasPrefix("chrome-extension://") {
            let allowed = "chrome-extension://\(NativeHostInstaller.savedExtensionID)/"
            if origin != allowed && origin + "/" != allowed {
                Logger.log("localhttp tolak origin: \(origin)")
                self.respond(conn, status: 403, json: ["ok": false, "message": "origin ditolak"])
                return
            }
        } else if let origin = headers["origin"], origin.hasPrefix("http") {
            Logger.log("localhttp tolak origin web: \(origin)")
            self.respond(conn, status: 403, json: ["ok": false, "message": "origin ditolak"])
            return
        }

        if method == "GET", path == "/ping" {
            self.respond(conn, status: 200, json: ["ok": true, "version": "1.0", "transport": "http"])
            return
        }
        guard method == "POST" else {
            self.respond(conn, status: 404, json: ["ok": false, "message": "tidak dikenal"])
            return
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            self.respond(conn, status: 400, json: ["ok": false, "message": "JSON tidak valid"])
            return
        }
        if path == "/add" {
            guard let url = obj["url"] as? String, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.respond(conn, status: 400, json: ["ok": false, "message": "URL kosong"])
                return
            }
            var headers: [String: String] = [:]
            if let c = obj["cookies"] as? String, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                headers["Cookie"] = c
            }
            if let r = obj["referer"] as? String, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                headers["Referer"] = r
            }
            // Profil browser asli (UA + client hint): cookie sesi situs hanya
            // sah bila UA-nya sama dengan browser yang menerbitkannya.
            if let profile = obj["profile"] as? [String: Any] {
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
                    for (k, v) in hints where !v.isEmpty { headers[k] = v }
                }
            }
            DispatchQueue.main.async {
                QueueManager.shared.addLinks(url, headers: headers)
            }
            let ua = (obj["profile"] as? [String: Any])?["userAgent"] as? String ?? ""
            Logger.log("localhttp add: \(url.prefix(60)) ua=\(ua.prefix(28)) cookies=\(!headers.isEmpty)")
            self.respond(conn, status: 200, json: ["ok": true, "transport": "http", "cookiesSent": !headers.isEmpty])
            return
        }
        if path == "/open-sheet" {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .gettoOpenAddSheet, object: nil)
            }
            self.respond(conn, status: 200, json: ["ok": true, "transport": "http"])
            return
        }
        self.respond(conn, status: 404, json: ["ok": false, "message": "tidak dikenal"])
    }

    private func respond(_ conn: NWConnection, status: Int, json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let text = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(text.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}
