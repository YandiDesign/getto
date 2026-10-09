import SwiftUI

/// Isi MenuBarExtra: ringkasan kecepatan + unduhan aktif + tempel cepat.
struct MenuBarView: View {
    @ObservedObject var queue: QueueManager

    var body: some View {
        let active = queue.items.filter { $0.status == .downloading }
        let totalSpeed = active.reduce(0) { $0 + $1.speedBytesPerSec }
        let isID = (Locale.preferredLanguages.first ?? "en").hasPrefix("id")
        Text("\(formatSpeed(totalSpeed)) • \(active.count) \(isID ? "aktif" : "active")")
            .font(.caption)
        Divider()
        if active.isEmpty {
            Text(NSLocalizedString("menubar.noActive", value: "Tidak ada unduhan aktif", comment: "")).font(.caption).foregroundColor(.secondary)
        } else {
            ForEach(active.prefix(5)) { item in
                VStack(alignment: .leading) {
                    Text(item.fileName).lineLimit(1)
                    ProgressView(value: item.progress).frame(width: 180)
                }
            }
        }
        Divider()
        Button(NSLocalizedString("menubar.paste", value: "Tempel link…", comment: "")) {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .gettoOpenAddSheet, object: nil)
        }
        Button(NSLocalizedString("menubar.open", value: "Buka Getto", comment: "")) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension Notification.Name {
    static let gettoOpenAddSheet = Notification.Name("getto.openAddSheet")
}
