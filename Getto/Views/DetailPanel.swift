import SwiftUI

// MARK: - Panel kanan: toolbar ikon, detail kaca, atau empty-state desain

struct DetailPanel: View {
    let item: DownloadItem?
    @ObservedObject var queue: QueueManager
    @Binding var showAdd: Bool
    @AppStorage("getto.appearance") private var appearance: String = "system"

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
                .padding(.horizontal, 16)
                .padding(.top, 14)
            if let item = item {
                detailContent(item)
            } else {
                emptyContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bar ikon kanan atas ala desain

    private var toolbarRow: some View {
        HStack {
            Spacer()
            HStack(spacing: 10) {
                GlassIconButton(systemImage: "plus", help: NSLocalizedString("add.title", value: "Tambah Unduhan", comment: "")) {
                    showAdd = true
                }
                GlassIconButton(systemImage: "link", help: NSLocalizedString("quickpaste", value: "Tempel link dari clipboard", comment: "")) {
                    let urls = ClipboardService.urlsInClipboard()
                    if urls.isEmpty {
                        showAdd = true
                    } else {
                        queue.addLinks(urls.joined(separator: "\n"))
                    }
                }
                GlassIconButton(imageName: "TurtleSlow", help: NSLocalizedString("slowmode", value: "Mode lambat (1 KB/s)", comment: ""), active: queue.slowMode) {
                    queue.toggleSlowMode()
                }
                GlassIconButton(systemImage: "power", help: NSLocalizedString("shutdown.toggle", value: "Matikan otomatis saat selesai", comment: ""), active: queue.settings.shutdownWhenDone) {
                    queue.settings.shutdownWhenDone.toggle()
                }
                GlassIconButton(systemImage: "slider.horizontal.3", help: NSLocalizedString("settings.title", value: "Pengaturan", comment: "")) {
                    // showSettingsWindow: = selector resmi pembuka scene Settings SwiftUI di macOS 13+
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                GlassIconButton(systemImage: appearanceIcon, help: NSLocalizedString("appearance.title", value: "Tampilan", comment: "")) {
                    cycleAppearance()
                }
            }
        }
    }

    private var appearanceIcon: String {
        switch appearance {
        case "light": return "sun.max.fill"
        case "dark": return "moon.fill"
        default: return "circle.lefthalf.filled"
        }
    }

    private func cycleAppearance() {
        switch appearance {
        case "system": appearance = "light"
        case "light": appearance = "dark"
        default: appearance = "system"
        }
    }

    // MARK: - Empty state ala desain

    private var emptyContent: some View {
        VStack {
            Spacer()
            ZStack {
                // Ikon kaca polos, tanpa efek bayangan/glow
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 128, height: 128)
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
                        )
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        .frame(width: 104, height: 104)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 26)
            .accessibilityHidden(true)

            Text(NSLocalizedString("detail.ready.title", value: "Siap untuk diunduh", comment: ""))
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text(NSLocalizedString("detail.ready.body", value: "Tempel link, pilih file, dan mulai unduh.\nSemua dalam satu tempat.", comment: ""))
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            Button {
                showAdd = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "link")
                        .font(.system(size: 13, weight: .semibold))
                    Text(NSLocalizedString("detail.ready.paste", value: "Tempel Link", comment: ""))
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.blue.opacity(0.5), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .noFocusRing()
            .padding(.top, 14)

            Spacer()
            speedCard
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
        }
    }

    private var speedCard: some View {
        let total = queue.items
            .filter { $0.status == .downloading }
            .reduce(Int64(0)) { $0 + $1.speedBytesPerSec }
        return HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("speed.now", value: "Kecepatan saat ini", comment: ""))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                Text(formatSpeed(total))
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
            }
            Spacer(minLength: 8)
            SpeedSparkline(samples: queue.speedHistory)
                .frame(width: 90, height: 30)
        }
        .padding(12)
        .glassCard(radius: 16, tint: .blue, showStroke: false)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(NSLocalizedString("speed.now", value: "Kecepatan saat ini", comment: "")): \(formatSpeed(total))")
    }

    // MARK: - Detail item terpilih

    private func detailContent(_ item: DownloadItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Hero — panel info item terpilih: tanpa outline (kebijakan panel kanan)
                HStack(spacing: 12) {
                    FileTile(fileName: item.fileName, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.fileName)
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .lineLimit(2)
                        statusPill(item.status)
                    }
                    Spacer()
                }
                .padding(14)
                .glassCard(tint: .accentColor, showStroke: false)

                // Statistik
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    statTile(NSLocalizedString("detail.size", value: "Ukuran", comment: ""),
                             "\(formatBytes(item.downloadedBytes)) / \(formatBytes(item.totalBytes))")
                    statTile(NSLocalizedString("detail.progress", value: "Progres", comment: ""),
                             String(format: "%.1f%%", item.progress * 100))
                    statTile(NSLocalizedString("detail.speed", value: "Kecepatan", comment: ""),
                             formatSpeed(item.speedBytesPerSec))
                    statTile("ETA", formatETA(item.etaSeconds))
                    if item.isTorrent {
                        statTile("Seeds", "\(item.numSeeds)")
                        statTile("Peers", "\(item.numPeers)")
                        statTile("Upload", formatSpeed(item.uploadSpeed))
                        statTile("Rasio", String(format: "%.2f", item.ratio))
                    }
                }

                if let phase = item.phaseDescription, item.isMedia || item.isTorrent {
                    Text(phase)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassCard(radius: 12, showStroke: false)
                }
                if let err = item.errorMessage, item.status == .failed {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassCard(radius: 12, showStroke: false)
                }

                // Aksi
                VStack(spacing: 8) {
                    if item.status == .completed {
                        actionButton(icon: "magnifyingglass", title: NSLocalizedString("detail.finder", value: "Tampilkan di Finder", comment: "")) {
                            NSWorkspace.shared.selectFile(item.destinationPath, inFileViewerRootedAtPath: (item.destinationPath as NSString).deletingLastPathComponent)
                        }
                        actionButton(icon: "eye", title: "Quick Look") {
                            _ = QuickLookService.shared.toggle(urls: [URL(fileURLWithPath: item.destinationPath)])
                        }
                        actionButton(icon: "doc.on.doc", title: NSLocalizedString("detail.copyLink", value: "Salin Link", comment: "")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.urlString, forType: .string)
                        }
                    }
                    if item.status == .failed {
                        actionButton(icon: "arrow.clockwise", title: NSLocalizedString("common.retry", value: "Coba Lagi", comment: "")) {
                            queue.retry(item)
                        }
                    }
                    if item.status == .downloading || item.status == .queued {
                        actionButton(icon: "pause.fill", title: NSLocalizedString("menu.pause", value: "Pause", comment: "")) { queue.pause(item) }
                    }
                    if item.status == .paused {
                        actionButton(icon: "play.fill", title: NSLocalizedString("menu.resume", value: "Resume", comment: "")) { queue.resume(item) }
                    }
                }

                // Sumber: situs asal + link berkas + file lokal, rapi & bisa diklik
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("detail.source", value: "Sumber", comment: ""))
                        .font(.system(size: 12, weight: .semibold))
                    sourceRow(
                        icon: "globe",
                        title: NSLocalizedString("detail.website", value: "Situs web", comment: ""),
                        value: item.websiteHost,
                        action: {
                            if let url = URL(string: item.urlString) { NSWorkspace.shared.open(url) }
                        }
                    )
                    sourceRow(
                        icon: "link",
                        title: NSLocalizedString("detail.fileLink", value: "Link berkas", comment: ""),
                        value: item.urlString,
                        action: {
                            if let url = URL(string: item.urlString) { NSWorkspace.shared.open(url) }
                        }
                    )
                    sourceRow(
                        icon: "folder",
                        title: NSLocalizedString("detail.localFile", value: "File lokal", comment: ""),
                        value: item.destinationPath,
                        action: {
                            NSWorkspace.shared.selectFile(item.destinationPath, inFileViewerRootedAtPath: (item.destinationPath as NSString).deletingLastPathComponent)
                        }
                    )
                }
                .padding(14)
                .glassCard(showStroke: false)
            }
            .padding(16)
        }
    }

    private func sourceRow(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                    Text(value.isEmpty ? "—" : value)
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .underline()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noFocusRing()
        .accessibilityLabel("\(title): \(value)")
    }

    private func statusPill(_ status: DownloadStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .downloading: return (NSLocalizedString("status.downloading", value: "Mengunduh", comment: ""), .blue)
            case .queued: return (NSLocalizedString("status.queued", value: "Menunggu", comment: ""), .orange)
            case .paused: return (NSLocalizedString("status.paused", value: "Jeda", comment: ""), .orange)
            case .completed: return (NSLocalizedString("status.done", value: "Selesai", comment: ""), .blue)
            case .failed: return (NSLocalizedString("status.failed", value: "Gagal", comment: ""), .red)
            case .seeding: return (NSLocalizedString("status.seeding", value: "Seeding", comment: ""), .purple)
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.gradient, in: Capsule())
            .shadow(color: color.opacity(0.4), radius: 5, y: 2)
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(radius: 14, showStroke: false)
    }

    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard(radius: 12, showStroke: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noFocusRing()
        .accessibilityLabel(title)
    }
}
