import AppKit
import Foundation

/// Baca isi clipboard; dipakai AddSheet untuk autofill URL.
enum ClipboardService {
    /// Semua URL http/https/magnet yang ditemukan di clipboard.
    static func urlsInClipboard() -> [String] {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return [] }
        // Dukung banyak link (satu per baris)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > 1 {
            return lines.filter { isDownloadableURL($0) }
        }
        if isDownloadableURL(text) { return [text] }
        return []
    }

    static func isDownloadableURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("magnet:?") { return true }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "ftp"].contains(scheme)
    }

    static func isVideoURL(_ s: String) -> Bool {
        let t = s.lowercased()
        return t.contains("youtube.com") || t.contains("youtu.be") || t.contains("tiktok.com")
            || t.contains("instagram.com") || t.contains("twitter.com") || t.contains("x.com")
            || t.contains("facebook.com") || t.contains("fb.watch") || t.contains("vimeo.com")
    }
}
