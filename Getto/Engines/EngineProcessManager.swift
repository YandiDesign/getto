import Foundation

/// Menjalankan & menghentikan binary pendukung (aria2c, yt-dlp, ffmpeg)
/// lewat Process dengan async/await + streaming output + cleanup saat keluar.
final class EngineProcessManager {
    static let shared = EngineProcessManager()
    private var running: [Process] = []
    private let lock = NSLock()

    private init() {}

    /// Subdirektori helper sesuai slice yang sedang berjalan
    /// (ditentukan saat kompilasi per-arch, tepat walau dipaksa Rosetta).
    #if arch(arm64)
    private let helperArchDir = "arm64"
    #else
    private let helperArchDir = "x86_64"
    #endif

    /// Path binary di dalam bundle: Contents/MacOS/bin/<arch>/<name> atau
    /// Resources/bin/<arch>/<name>.
    /// Fallback ke Resources/bin/<name> (kompatibilitas) lalu ke PATH sistem.
    func binaryPath(named name: String) -> URL? {
        let fm = FileManager.default
        let bundleBin = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/bin/\(helperArchDir)/\(name)")
        if fm.isExecutableFile(atPath: bundleBin.path) { return bundleBin }
        if let resDir = Bundle.main.resourceURL?.appendingPathComponent("bin/\(helperArchDir)", isDirectory: true) {
            let candidate = resDir.appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        if let res = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "bin") {
            if fm.isExecutableFile(atPath: res.path) { return res }
        }
        // Fallback PATH (berguna saat dev tanpa bundle penuh)
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/opt/miniconda3/bin", "/usr/bin"] {
            let p = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }

    @discardableResult
    func launch(executable: URL, arguments: [String], onLine: ((String) -> Void)? = nil) throws -> Process {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        if let onLine = onLine {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                    onLine(line)
                }
            }
        }
        try p.run()
        lock.lock(); running.append(p); lock.unlock()
        return p
    }

    func terminateAll() {
        lock.lock(); let procs = running; running.removeAll(); lock.unlock()
        for p in procs where p.isRunning { p.terminate() }
    }

    /// Jalankan sekali & tunggu selesai, kembalikan output + exit code.
    func runOnce(executable: URL, arguments: [String], timeout: TimeInterval = 120) async throws -> (output: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { cont in
            do {
                let p = Process()
                p.executableURL = executable
                p.arguments = arguments
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                // Kuras pipe selama proses berjalan agar output besar (dump-json)
                // tidak deadlock memenuhi buffer pipe 64KB.
                final class OutputBox { var data = Data() }
                let box = OutputBox()
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if !chunk.isEmpty { box.data.append(chunk) }
                }
                p.terminationHandler = { proc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    box.data.append(pipe.fileHandleForReading.readDataToEndOfFile())
                    let out = String(data: box.data, encoding: .utf8) ?? ""
                    cont.resume(returning: (out, proc.terminationStatus))
                }
                try p.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if p.isRunning { p.terminate() }
                }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
