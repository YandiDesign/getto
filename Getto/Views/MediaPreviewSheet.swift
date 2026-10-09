import SwiftUI

/// Pratinjau video terpisah (dipakai ulang dari AddSheet bila diperlukan).
struct MediaPreviewSheet: View {
    let info: MediaInfo
    @Binding var options: MediaOptions
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: info.thumbnailURL ?? "")) { img in
                img.resizable().scaledToFit().frame(width: 160)
            } placeholder: {
                Image(systemName: "photo").frame(width: 160)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title).font(.headline).lineLimit(2)
                if let ch = info.channel { Text(ch).font(.subheadline).foregroundColor(.secondary) }
                Text(info.durationString).font(.caption).foregroundColor(.secondary)
                Picker(NSLocalizedString("add.quality", value: "Kualitas", comment: ""), selection: $options.quality) {
                    ForEach(MediaQuality.allCases, id: \.self) { q in Text(q.label).tag(q) }
                }
            }
        }
        .padding()
    }
}
