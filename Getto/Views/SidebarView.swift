import SwiftUI

// MARK: - Sidebar custom transparan: pill biru, badge, kategori.
// Transparan agar gradien jendela tembus (kaca biru seperti referensi),
// bukan panel abu native.

struct SidebarView: View {
    @Binding var selection: SidebarSelection
    @ObservedObject var queue: QueueManager
    @Environment(\.colorScheme) private var scheme

    private let library: [(SidebarSelection, String, String)] = [
        (.all, "arrow.down.circle", NSLocalizedString("sidebar.all", value: "Semua Unduhan", comment: "")),
        (.active, "clock", NSLocalizedString("sidebar.active", value: "Sedang Berjalan", comment: "")),
        (.completed, "checkmark.circle", NSLocalizedString("sidebar.done", value: "Selesai", comment: "")),
        (.torrents, "arrow.2.circlepath", "Torrent"),
        (.media, "play.rectangle", NSLocalizedString("sidebar.media", value: "Video & Audio", comment: "")),
        (.failed, "xmark.circle", NSLocalizedString("sidebar.failed", value: "Gagal", comment: "")),
    ]

    private let categories: [(SidebarSelection, String, String)] = [
        (.documents, "folder", NSLocalizedString("cat.documents", value: "Dokumen", comment: "")),
        (.archives, "archivebox", NSLocalizedString("cat.archives", value: "Arsip", comment: "")),
        (.images, "photo", NSLocalizedString("cat.images", value: "Gambar", comment: "")),
        (.music, "music.note", NSLocalizedString("cat.music", value: "Musik", comment: "")),
        (.videos, "film", NSLocalizedString("cat.videos", value: "Video", comment: "")),
        (.apps, "app.badge", NSLocalizedString("cat.apps", value: "Aplikasi", comment: "")),
    ]

    var body: some View {
        ZStack {
            AppBackground()
            // Veil terang agar sidebar terbaca sebagai panel kaca menyatu
            Color.white.opacity(scheme == .dark ? 0.05 : 0.20).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                // Ruang untuk traffic lights (hiddenTitleBar)
                Spacer().frame(height: 26)

                // Header app
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.blue.gradient)
                            .frame(width: 36, height: 36)
                            .shadow(color: Color.blue.opacity(0.5), radius: 8, y: 3)
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Getto")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Getto")

                VStack(spacing: 2) {
                    ForEach(library, id: \.0) { item in
                        SidebarRow(sel: item.0, icon: item.1, title: item.2,
                                  count: count(for: item.0), selected: selection == item.0) {
                            selection = item.0
                        }
                    }
                }

                HStack {
                    Text(NSLocalizedString("sidebar.section.categories", value: "Kategori", comment: ""))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .accessibilityHidden(true)

                VStack(spacing: 2) {
                    ForEach(categories, id: \.0) { item in
                        SidebarRow(sel: item.0, icon: item.1, title: item.2,
                                  count: count(for: item.0), selected: selection == item.0) {
                            selection = item.0
                        }
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 10)
            }
        }
    }

    private func count(for sel: SidebarSelection) -> Int {
        switch sel {
        case .all: return queue.items.count
        case .active: return queue.items.filter { $0.status == .downloading }.count
        case .completed: return queue.items.filter { $0.status == .completed }.count
        case .torrents: return queue.items.filter { $0.isTorrent }.count
        case .media: return queue.items.filter { $0.isMedia }.count
        case .failed: return queue.items.filter { $0.status == .failed }.count
        case .queued: return queue.items.filter { $0.status == .queued || $0.status == .paused }.count
        default: return queue.items.filter { $0.fileCategory == sel }.count
        }
    }
}

private struct SidebarRow: View {
    let sel: SidebarSelection
    let icon: String
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .medium))
                    .frame(width: 19)
                    .foregroundColor(selected ? .white.opacity(0.95) : .secondary)
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .white : .primary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(selected ? .white.opacity(0.92) : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(selected ? Color.white.opacity(0.28) : Color.primary.opacity(0.09))
                        )
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.blue : (hovering ? Color.white.opacity(0.12) : Color.clear))
                    .shadow(color: selected ? Color.blue.opacity(0.45) : .clear, radius: 7, y: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
