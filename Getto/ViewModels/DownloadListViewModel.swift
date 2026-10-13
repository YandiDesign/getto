import Foundation
import Combine
import SwiftUI

enum SortOrder: String, CaseIterable {
    case newest
    case oldest
    case az
    case za
    case biggest
    case smallest

    var label: String {
        switch self {
        case .newest: return NSLocalizedString("sort.newest", value: "Terbaru", comment: "")
        case .oldest: return NSLocalizedString("sort.oldest", value: "Terlama", comment: "")
        case .az: return "A–Z"
        case .za: return "Z–A"
        case .biggest: return NSLocalizedString("sort.biggest", value: "Ukuran terbesar", comment: "")
        case .smallest: return NSLocalizedString("sort.smallest", value: "Ukuran terkecil", comment: "")
        }
    }
}

/// Filter daftar unduhan berdasarkan sidebar + pencarian.
final class DownloadListViewModel: ObservableObject {
    static let shared = DownloadListViewModel()

    @Published var selection: SidebarSelection = .all
    @Published var searchText: String = ""
    @Published var selectedId: UUID?
    @Published var layoutGrid: Bool = false
    /// Mode multi-pilih: kartu menampilkan centang, baris aksi bawah aktif.
    @Published var selectionMode: Bool = false
    /// Unduhan yang dicentang saat mode pilih aktif.
    @Published var selectedIds: Set<UUID> = []
    @Published var sortOrder: SortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: "getto.sort") ?? SortOrder.newest.rawValue) ?? .newest {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "getto.sort") }
    }

    // MARK: - Mode pilih

    var hasChecked: Bool { !selectedIds.isEmpty }

    func enterSelectionMode() { selectionMode = true }

    func exitSelectionMode() {
        selectionMode = false
        selectedIds.removeAll()
    }

    func isChecked(_ item: DownloadItem) -> Bool { selectedIds.contains(item.id) }

    func toggleCheck(_ item: DownloadItem) {
        if selectedIds.contains(item.id) { selectedIds.remove(item.id) }
        else { selectedIds.insert(item.id) }
    }

    /// Pilih semua unduhan yang sedang terlihat (hasil filter + pencarian).
    func setAllChecked(_ checked: Bool, in list: [DownloadItem]) {
        if checked {
            selectedIds.formUnion(list.map(\.id))
        } else {
            selectedIds.subtract(list.map(\.id))
        }
    }

    func allChecked(in list: [DownloadItem]) -> Bool {
        !list.isEmpty && list.allSatisfy { selectedIds.contains($0.id) }
    }

    /// Unduhan yang dicentang, urut sesuai antrean.
    func checkedItems(from items: [DownloadItem]) -> [DownloadItem] {
        items.filter { selectedIds.contains($0.id) }
    }

    /// Buang id yang sudah tidak ada di antrean (setelah unduhan dihapus).
    /// Mode pilih TIDAK dimatikan hanya karena belum ada yang dicentang —
    /// kalau begitu mode akan langsung hilang saat baru dinyalakan.
    func pruneSelection(_ items: [DownloadItem]) {
        guard !selectedIds.isEmpty else { return }
        let alive = Set(items.map(\.id))
        let pruned = selectedIds.intersection(alive)
        guard pruned != selectedIds else { return }
        selectedIds = pruned
        if selectedIds.isEmpty { selectionMode = false }
    }

    func filtered(_ items: [DownloadItem]) -> [DownloadItem] {
        var list = items
        switch selection {
        case .all: break
        case .active: list = list.filter { $0.status == .downloading }
        case .queued: list = list.filter { $0.status == .queued || $0.status == .paused }
        case .completed: list = list.filter { $0.status == .completed }
        case .torrents: list = list.filter { $0.isTorrent }
        case .media: list = list.filter { $0.isMedia }
        case .failed: list = list.filter { $0.status == .failed }
        case .documents, .archives, .images, .music, .videos, .apps:
            list = list.filter { $0.fileCategory == selection }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter { $0.fileName.lowercased().contains(q) || $0.urlString.lowercased().contains(q) }
        }
        return sortItems(list)
    }

    private func effectiveSize(_ item: DownloadItem) -> Int64 {
        max(item.totalBytes, item.downloadedBytes)
    }

    func sortItems(_ list: [DownloadItem]) -> [DownloadItem] {
        switch sortOrder {
        case .newest:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return list.sorted { $0.createdAt < $1.createdAt }
        case .az:
            return list.sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
        case .za:
            return list.sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedDescending }
        case .biggest:
            return list.sorted { effectiveSize($0) > effectiveSize($1) }
        case .smallest:
            return list.sorted { effectiveSize($0) < effectiveSize($1) }
        }
    }

    /// Judul header saat mode multi-pilih aktif.
    func selectionSubtitle() -> String {
        if selectedIds.isEmpty {
            return NSLocalizedString("select.title", value: "Pilih Unduhan", comment: "")
        }
        return String(format: NSLocalizedString("select.titleCount", value: "%d Dipilih", comment: ""), selectedIds.count)
    }

    func title() -> String {
        switch selection {
        case .all: return NSLocalizedString("sidebar.all", value: "Semua Unduhan", comment: "")
        case .active: return NSLocalizedString("sidebar.active", value: "Sedang Berjalan", comment: "")
        case .queued: return NSLocalizedString("sidebar.queued", value: "Antre", comment: "")
        case .completed: return NSLocalizedString("sidebar.done", value: "Selesai", comment: "")
        case .torrents: return "Torrent"
        case .media: return NSLocalizedString("sidebar.media", value: "Video & Audio", comment: "")
        case .failed: return NSLocalizedString("sidebar.failed", value: "Gagal", comment: "")
        case .documents: return NSLocalizedString("cat.documents", value: "Dokumen", comment: "")
        case .archives: return NSLocalizedString("cat.archives", value: "Arsip", comment: "")
        case .images: return NSLocalizedString("cat.images", value: "Gambar", comment: "")
        case .music: return NSLocalizedString("cat.music", value: "Musik", comment: "")
        case .videos: return NSLocalizedString("cat.videos", value: "Video", comment: "")
        case .apps: return NSLocalizedString("cat.apps", value: "Aplikasi", comment: "")
        }
    }
}
