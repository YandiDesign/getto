import SwiftUI
import AppKit

// MARK: - Kolom daftar: search kaca, judul, kartu unduhan, mode grid

struct DownloadListView: View {
    @ObservedObject var queue: QueueManager
    @ObservedObject var vm: DownloadListViewModel
    @Binding var selectedId: UUID?
    @Binding var detailVisible: Bool

    var body: some View {
        let list = vm.filtered(queue.items)
        VStack(alignment: .leading, spacing: 12) {
            // Search kaca
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .medium))
                TextField(
                    NSLocalizedString("search.placeholder", value: "Cari atau tempel link…", comment: ""),
                    text: $vm.searchText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                if !vm.searchText.isEmpty {
                    Button { vm.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("common.clear", value: "Hapus", comment: ""))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Judul + toggle
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.title())
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(listSubtitle(count: list.count))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    SortMenuButton(vm: vm)
                    layoutButton(grid: false, icon: "list.bullet")
                    layoutButton(grid: true, icon: "square.grid.2x2")
                }
                .padding(3)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            }
            .padding(.horizontal, 18)

            // Isi
            if list.isEmpty {
                emptyState
            } else if vm.layoutGrid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(list) { item in
                            DownloadTile(item: item, queue: queue, selected: selectedId == item.id)
                                .onTapGesture { select(item) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(list) { item in
                            DownloadCard(item: item, queue: queue, selected: selectedId == item.id)
                                .onTapGesture { select(item) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func select(_ item: DownloadItem) {
        selectedId = item.id
        // Lepas fokus dari kontrol/teks agar Space berikutnya = Quick Look,
        // bukan mengaktifkan tombol atau mengetik di kolom cari.
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func layoutButton(grid: Bool, icon: String) -> some View {
        Button { vm.layoutGrid = grid } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(vm.layoutGrid == grid ? .white : .secondary)
                .frame(width: 36, height: 30)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(vm.layoutGrid == grid ? Color.blue : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(grid
            ? NSLocalizedString("layout.grid", value: "Tampilan grid", comment: "")
            : NSLocalizedString("layout.list", value: "Tampilan daftar", comment: ""))
    }

    private func listSubtitle(count: Int) -> String {
        let active = queue.items.filter { $0.status == .downloading }.count
        let isID = (Locale.preferredLanguages.first ?? "en").hasPrefix("id")
        if active > 0 {
            return isID ? "\(count) item • \(active) sedang berjalan" : "\(count) items • \(active) active"
        }
        return isID ? "\(count) item" : "\(count) items"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.8))
            Text(NSLocalizedString("list.empty", value: "Belum ada unduhan. Tekan + atau ⌘N untuk menambah.", comment: ""))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tombol sortir (popover, bukan Menu)

struct SortMenuButton: View {
    @ObservedObject var vm: DownloadListViewModel
    @State private var showMenu = false

    var body: some View {
        Button { showMenu.toggle() } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 36, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showMenu, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("sort.title", value: "Urutkan", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                ForEach(SortOrder.allCases, id: \.self) { o in
                    Button {
                        vm.sortOrder = o
                        showMenu = false
                    } label: {
                        HStack {
                            Text(o.label)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                            Spacer()
                            if vm.sortOrder == o {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(o.label)
                }
            }
            .padding(8)
            .frame(minWidth: 200)
        }
        .help(NSLocalizedString("sort.title", value: "Urutkan", comment: ""))
        .accessibilityLabel(NSLocalizedString("sort.title", value: "Urutkan", comment: ""))
    }
}

// MARK: - Kartu baris unduhan

struct DownloadCard: View {
    let item: DownloadItem
    @ObservedObject var queue: QueueManager
    var selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            thumb
            VStack(alignment: .leading, spacing: 5) {
                Text(item.fileName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.status == .downloading {
                    HStack(spacing: 8) {
                        CapsuleProgressBar(progress: item.progress)
                        Text("\(Int(item.progress * 100))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                Text(itemSubtitleLine(item))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(item.status == .failed ? 2 : 1)
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(12)
        .glassCard(tint: selected ? .accentColor : nil, showStroke: selected)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 1.5)
        )
        .contextMenu { rowMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.fileName), \(itemSubtitleLine(item))")
    }

    @ViewBuilder
    private var thumb: some View {
        let ext = (item.fileName as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(ext),
           item.status == .completed {
            AsyncImage(url: URL(fileURLWithPath: item.destinationPath)) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                FileTile(fileName: item.fileName)
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            FileTile(fileName: item.fileName, showPlayBadge: ["mp4", "mkv", "webm", "mov", "avi"].contains(ext))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 6) {
            switch item.status {
            case .downloading, .queued:
                Button { queue.pause(item) } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.28)))
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("menu.pause", value: "Pause", comment: ""))
            case .paused, .failed:
                Button { queue.resume(item) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("menu.resume", value: "Resume", comment: ""))
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.4), radius: 4)
            case .seeding:
                Button { queue.pause(item) } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.28)))
                }
                .buttonStyle(.plain)
            }
            CardMenuButton(item: item, queue: queue)
        }
    }

    // MARK: - Tombol "..." popover (pengganti Menu yang flaky di macOS 13)

    /// Tombol menu deterministik: Button biasa + popover, selalu terbuka saat
    /// diklik (Menu borderless + onTapGesture induk bermasalah di macOS 13).
    struct CardMenuButton: View {
        let item: DownloadItem
        @ObservedObject var queue: QueueManager
        @State private var showMenu = false

        var body: some View {
            Button { showMenu.toggle() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary.opacity(0.75))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showMenu, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 2) {
                    menuRows
                }
                .padding(8)
                .frame(minWidth: 200)
            }
            .accessibilityLabel("Menu")
        }

        private func dismissThen(_ action: @escaping () -> Void) {
            showMenu = false
            action()
        }

        @ViewBuilder
        private var menuRows: some View {
            if item.status == .downloading || item.status == .queued {
                menuRow("pause.fill", NSLocalizedString("menu.pause", value: "Pause", comment: "")) {
                    dismissThen { queue.pause(item) }
                }
            }
            if item.status == .paused || item.status == .failed {
                menuRow("play.fill", NSLocalizedString("menu.resume", value: "Resume", comment: "")) {
                    dismissThen { queue.resume(item) }
                }
                menuRow("arrow.clockwise", NSLocalizedString("menu.retry", value: "Unduh Ulang", comment: "")) {
                    dismissThen { queue.retry(item) }
                }
            }
            menuRow("link", NSLocalizedString("menu.copyLink", value: "Salin Link", comment: "")) {
                dismissThen {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.urlString, forType: .string)
                }
            }
            if item.status == .completed {
                menuRow("eye", "Quick Look") {
                    dismissThen { _ = QuickLookService.shared.toggle(urls: [URL(fileURLWithPath: item.destinationPath)]) }
                }
                menuRow("doc.on.doc", NSLocalizedString("menu.openFile", value: "Buka File", comment: "")) {
                    dismissThen { NSWorkspace.shared.open(URL(fileURLWithPath: item.destinationPath)) }
                }
                menuRow("magnifyingglass", NSLocalizedString("menu.showFinder", value: "Tampilkan di Finder", comment: "")) {
                    dismissThen {
                        NSWorkspace.shared.selectFile(item.destinationPath, inFileViewerRootedAtPath: (item.destinationPath as NSString).deletingLastPathComponent)
                    }
                }
            }
            Divider()
            menuRow("trash", NSLocalizedString("menu.delete", value: "Hapus", comment: ""), destructive: true) {
                dismissThen { queue.cancel(item) }
            }
        }

        private func menuRow(_ icon: String, _ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Label(title, systemImage: icon)
                    .font(.system(size: 13))
                    .foregroundColor(destructive ? .red : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private var rowMenu: some View {
        if item.status == .downloading || item.status == .queued {
            Button(NSLocalizedString("menu.pause", value: "Pause", comment: "")) { queue.pause(item) }
        }
        if item.status == .paused || item.status == .failed {
            Button(NSLocalizedString("menu.resume", value: "Resume", comment: "")) { queue.resume(item) }
            Button(NSLocalizedString("menu.retry", value: "Unduh Ulang", comment: "")) { queue.retry(item) }
        }
        Button(NSLocalizedString("menu.copyLink", value: "Salin Link", comment: "")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.urlString, forType: .string)
        }
        if item.status == .completed {
            Button("Quick Look") {
                _ = QuickLookService.shared.toggle(urls: [URL(fileURLWithPath: item.destinationPath)])
            }
            Button(NSLocalizedString("menu.openFile", value: "Buka File", comment: "")) { NSWorkspace.shared.open(URL(fileURLWithPath: item.destinationPath)) }
            Button(NSLocalizedString("menu.showFinder", value: "Tampilkan di Finder", comment: "")) {
                NSWorkspace.shared.selectFile(item.destinationPath, inFileViewerRootedAtPath: (item.destinationPath as NSString).deletingLastPathComponent)
            }
        }
        Divider()
        Button(NSLocalizedString("menu.delete", value: "Hapus", comment: ""), role: .destructive) { queue.cancel(item) }
    }
}

// MARK: - Tile grid kompak

struct DownloadTile: View {
    let item: DownloadItem
    @ObservedObject var queue: QueueManager
    var selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FileTile(fileName: item.fileName, size: 40)
                Spacer()
                if item.status == .completed {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.blue).font(.system(size: 20))
                } else if item.status == .failed {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red).font(.system(size: 20))
                } else {
                    DownloadCard.CardMenuButton(item: item, queue: queue)
                }
            }
            Text(item.fileName)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.middle)
            if item.status == .downloading {
                CapsuleProgressBar(progress: item.progress, height: 5)
                Text("\(Int(item.progress * 100))% • \(formatSpeed(item.speedBytesPerSec))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text(itemSubtitleLine(item))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .glassCard(tint: selected ? .accentColor : nil, showStroke: selected)
        .contextMenu {
            Button(NSLocalizedString("menu.delete", value: "Hapus", comment: ""), role: .destructive) { queue.cancel(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.fileName), \(itemSubtitleLine(item))")
    }
}
