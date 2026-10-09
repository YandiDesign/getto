import SwiftUI

// MARK: - Format angka (dipakai lintas view)

func formatBytes(_ n: Int64) -> String {
    guard n > 0 else { return "—" }
    let b = Double(n)
    if b >= 1_073_741_824 { return String(format: "%.1f GB", b / 1_073_741_824) }
    if b >= 1_048_576 { return String(format: "%.1f MB", b / 1_048_576) }
    if b >= 1024 { return String(format: "%.0f KB", b / 1024) }
    return "\(n) B"
}

func formatSpeed(_ n: Int64) -> String {
    guard n > 0 else { return "—" }
    return formatBytes(n) + "/s"
}

func formatETA(_ s: Int64) -> String {
    guard s > 0 else { return "—" }
    if s >= 3600 { return String(format: "%d jam %d mnt", s / 3600, (s % 3600) / 60) }
    if s >= 60 { return String(format: "%d mnt %d dtk", s / 60, s % 60) }
    return "\(s) dtk"
}

func iconForFile(_ name: String) -> String {
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "pdf": return "doc.richtext"
    case "zip", "rar", "7z", "tar", "gz": return "archivebox"
    case "dmg", "pkg", "iso", "app": return "app.badge"
    case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
    case "mp3", "m4a", "opus", "flac", "wav", "aac": return "music.note"
    case "mp4", "mkv", "webm", "mov", "avi": return "film"
    case "torrent": return "magnet"
    default: return "doc"
    }
}

// MARK: - Latar polos jendela (flat solid, terang/gelap adaptif)

struct AppBackground: View {
    @Environment(\.colorScheme) var scheme

    var body: some View {
        (scheme == .dark
            ? Color(red: 0.11, green: 0.14, blue: 0.25)
            : Color(red: 0.90, green: 0.92, blue: 0.95))
            .ignoresSafeArea()
    }
}

// MARK: - Kartu kaca

struct GlassCard: ViewModifier {
    var radius: CGFloat = 18
    var tint: Color? = nil
    /// Outline hanya untuk kartu yang dipilih/aktif; kartu biasa tanpa outline.
    var showStroke: Bool = true

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill((tint ?? .white).opacity(tint == nil ? 0.10 : 0.20))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(showStroke ? 0.32 : 0.0), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 14, y: 7)
    }
}

extension View {
    func glassCard(radius: CGFloat = 18, tint: Color? = nil, showStroke: Bool = true) -> some View {
        modifier(GlassCard(radius: radius, tint: tint, showStroke: showStroke))
    }
}

// MARK: - Tombol ikon toolbar ala desain

struct GlassIconButton: View {
    let systemImage: String?
    let imageName: String?
    let help: String
    let active: Bool
    let action: () -> Void

    init(systemImage: String? = nil, imageName: String? = nil, help: String, active: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.imageName = imageName
        self.help = help
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let imageName = imageName {
                    Image(imageName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                } else {
                    Image(systemName: systemImage ?? "circle")
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .foregroundColor(active ? .white : .primary)
            .frame(width: 38, height: 38)
            .contentShape(Circle())
            .background(
                (active ? Color.blue : Color.clear)
                    .opacity(active ? 1 : 0),
                in: Circle()
            )
            .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .overlay(Circle().strokeBorder(active ? Color.blue : Color.white.opacity(0.3), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .contentShape(Circle())
        .help(help + (active ? " (aktif)" : ""))
        .accessibilityLabel(help)
    }
}

// MARK: - Tile ikon file berwarna

func tileColor(for fileName: String) -> Color {
    let ext = (fileName as NSString).pathExtension.lowercased()
    switch ext {
    case "mp4", "mkv", "webm", "mov", "avi": return .blue
    case "mp3", "m4a", "opus", "flac", "wav", "aac", "ogg": return .pink
    case "png", "jpg", "jpeg", "gif", "webp", "heic": return .green
    case "zip", "rar", "7z", "tar", "gz", "dmg", "pkg", "iso": return .orange
    case "pdf", "doc", "docx", "txt", "md": return .red
    case "torrent", "magnet": return .purple
    default: return .blue
    }
}

struct FileTile: View {
    let fileName: String
    var size: CGFloat = 46
    var showPlayBadge: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tileColor(for: fileName).gradient)
                .frame(width: size, height: size)
                .shadow(color: tileColor(for: fileName).opacity(0.4), radius: 6, y: 3)
            Image(systemName: iconForFile(fileName))
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundColor(.white)
            if showPlayBadge {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: size * 0.34))
                    .foregroundColor(.white)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .offset(x: size * 0.28, y: size * 0.28)
            }
        }
    }
}

// MARK: - Bar progres kapsul

struct CapsuleProgressBar: View {
    var progress: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: height)
                Capsule()
                    .fill(Color.white.gradient)
                    .frame(width: max(0, geo.size.width * min(1, max(0, progress))), height: height)
                    .shadow(color: .white.opacity(0.5), radius: 3)
                    .animation(.easeInOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Sparkline kecepatan (kurva halus Catmull-Rom)

struct SpeedSparkline: View {
    var samples: [Double]
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                smoothPath(pts)
                    .stroke(color.opacity(0.9), lineWidth: 1.6)
                areaPath(pts, size: geo.size)
                    .fill(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let vals = normalized()
        guard !vals.isEmpty else { return [] }
        if vals.count == 1 {
            return [CGPoint(x: 0, y: size.height - vals[0] * size.height),
                    CGPoint(x: size.width, y: size.height - vals[0] * size.height)]
        }
        return vals.enumerated().map { i, v in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(vals.count - 1),
                    y: size.height - v * size.height)
        }
    }

    /// Kurva Bezier kubik halus melalui semua titik (Catmull-Rom → Bezier).
    private func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(pts.count - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private func normalized() -> [Double] {
        guard let maxV = samples.max(), maxV > 0 else { return samples.map { _ in 0 } }
        return samples.map { max(0.04, $0 / maxV) }
    }

    /// Area arsir di bawah kurva (kurva + tutup ke bawah).
    private func areaPath(_ pts: [CGPoint], size: CGSize) -> Path {
        var path = smoothPath(pts)
        if let first = pts.first, let last = pts.last {
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.addLine(to: CGPoint(x: first.x, y: size.height))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Waktu relatif (id/en)

func relativeTimeString(from date: Date) -> String {
    let isID = (Locale.preferredLanguages.first ?? "en").hasPrefix("id")
    let mins = Int(Date().timeIntervalSince(date) / 60)
    if mins < 1 { return isID ? "baru saja" : "just now" }
    if mins < 60 { return isID ? "\(mins) menit yang lalu" : "\(mins) minutes ago" }
    let hours = mins / 60
    if hours < 24 { return isID ? "\(hours) jam yang lalu" : "\(hours) hours ago" }
    let days = hours / 24
    return isID ? "\(days) hari yang lalu" : "\(days) days ago"
}

func itemSubtitleLine(_ item: DownloadItem) -> String {
    let size = formatBytes(item.totalBytes > 0 ? item.totalBytes : item.downloadedBytes)
    if item.status == .completed, let done = item.completedAt {
        return "\(size) • \(relativeTimeString(from: done))"
    }
    if item.status == .downloading {
        return "\(formatBytes(item.downloadedBytes)) / \(formatBytes(item.totalBytes)) • \(formatSpeed(item.speedBytesPerSec))"
    }
    if item.status == .paused {
        return "\(NSLocalizedString("status.paused", value: "Jeda", comment: "")) • \(size)"
    }
    if item.status == .failed {
        return item.errorMessage ?? NSLocalizedString("status.failed", value: "Gagal", comment: "")
    }
    return "\(NSLocalizedString("status.queued", value: "Menunggu", comment: "")) • \(size)"
}
