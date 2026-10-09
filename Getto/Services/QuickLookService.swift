import AppKit
import Foundation
import QuickLookUI

/// Quick Look (panel pratinjau Space) untuk file hasil unduhan.
/// Dipicu lewat monitor tombol Space (lihat AppDelegate) atau menu konteks.
final class QuickLookService: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookService()

    private var urls: [URL] = []
    private override init() { super.init() }

    /// Logika murni (bisa diuji): kapan Space boleh membuka pratinjau?
    /// - Hanya item selesai yang filenya ada.
    /// - Jangan rebut Space dari kolom teks (NSTextView) atau tombol/kontrol fokus (NSControl).
    static func shouldPreview(item: DownloadItem?, firstResponder: NSResponder?) -> Bool {
        if firstResponder is NSTextView { return false }
        if firstResponder is NSControl { return false }
        guard let item = item, item.status == .completed else { return false }
        return FileManager.default.fileExists(atPath: item.destinationPath)
    }

    /// Tampilkan/sembunyikan panel. Kembalikan false bila tak ada file valid.
    @discardableResult
    func toggle(urls: [URL]) -> Bool {        let valid = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !valid.isEmpty else { return false }
        self.urls = valid
        guard let panel = QLPreviewPanel.shared() else { return false }
        panel.dataSource = self
        panel.reloadData()
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}

// MARK: - Aksi tombol keyboard (logika murni, bisa diuji)

enum KeyAction {
    case none
    case clearSelection
    case quickLook
}

struct KeyHandler {
    /// Tentukan aksi untuk keyDown.
    /// - keyCode: 49 = Space, 53 = Escape
    /// - inTextOrControl: fokus di kolom teks/kontrol (jangan rebut tombolnya)
    /// - searchEmpty: isi kolom cari kosong (Escape aman menghapus seleksi)
    /// - sheetOpen: sheet menempel (biarkan perilaku native)
    static func resolve(keyCode: UInt16, modifiersEmpty: Bool, characters: String?,
                        inTextOrControl: Bool, searchEmpty: Bool, sheetOpen: Bool,
                        hasSelection: Bool, previewable: Bool) -> KeyAction {
        if keyCode == 53 { // Escape
            if sheetOpen { return .none }
            if !hasSelection { return .none }
            // Di kolom teks berisi: biarkan native (mis. batalkan edit / kosongkan cari).
            if inTextOrControl && !searchEmpty { return .none }
            return .clearSelection
        }
        if keyCode == 49, modifiersEmpty, characters == " " { // Space
            if sheetOpen { return .none }
            if inTextOrControl { return .none }
            return previewable ? .quickLook : .none
        }
        return .none
    }
}
