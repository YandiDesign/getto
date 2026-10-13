import SwiftUI
import AppKit

// MARK: - Pilihan hapus: hapus berkas di disk, atau cukup dari daftar

/// Sheet konfirmasi hapus dengan dua pilihan:
/// 1. "Hapus File" — berkas ikut hilang (dipindahkan ke Sampah).
/// 2. "Hapus dari Daftar Saja" — berkas tetap ada di folder unduhan.
struct DeleteDownloadsSheet: View {
    let targets: [DownloadItem]
    let onDeleteFiles: () -> Void
    let onRemoveFromList: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var isSingle: Bool { targets.count == 1 }

    private var title: String {
        if isSingle {
            return NSLocalizedString("delete.title.single", value: "Hapus unduhan ini?", comment: "")
        }
        let fmt = NSLocalizedString("delete.title.multi", value: "Hapus %d unduhan?", comment: "")
        return String(format: fmt, targets.count)
    }

    private var subtitleName: String? {
        isSingle ? targets.first?.fileName : nil
    }

    /// Hanya berkas yang benar-benar ada di disk yang bisa dihapus.
    private var deletable: [DownloadItem] {
        targets.filter { FileManager.default.fileExists(atPath: $0.destinationPath) }
    }

    private var freedBytes: Int64 {
        deletable.reduce(0) { $0 + max($1.totalBytes, $1.downloadedBytes) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.red)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.red.opacity(0.12)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                    if let subtitleName {
                        Text(subtitleName)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    if deletable.isEmpty {
                        Text(NSLocalizedString("delete.body.noFile",
                                              value: "Tidak ada berkas unduhan di disk untuk item ini.",
                                              comment: ""))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else if freedBytes > 0 {
                        Text(String(format: NSLocalizedString("delete.body.free", value: "%@ akan dipindahkan ke Sampah.", comment: ""),
                                   formatBytes(freedBytes)))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if !deletable.isEmpty {
                    actionButton(
                        "trash.fill",
                        NSLocalizedString("delete.action.files", value: "Hapus File", comment: ""),
                        NSLocalizedString("delete.action.files.sub", value: "Berkas dipindahkan ke Sampah dan dihapus dari daftar", comment: ""),
                        destructive: true
                    ) {
                        onDeleteFiles()
                        dismiss()
                    }
                }
                actionButton(
                    "text.badge.minus",
                    NSLocalizedString("delete.action.listOnly", value: "Hapus dari Daftar Saja", comment: ""),
                    NSLocalizedString("delete.action.listOnly.sub", value: "Berkas tetap disimpan di folder unduhan", comment: ""),
                    destructive: false
                ) {
                    onRemoveFromList()
                    dismiss()
                }
                actionButton(
                    "xmark",
                    NSLocalizedString("common.cancel", value: "Batal", comment: ""),
                    nil,
                    destructive: false,
                    compact: true
                ) { dismiss() }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 430)
        // Esc selalu menutup sheet ini, karena tombolnya tidak bisa difokuskan
        // (noFocusRing) sehingga keyboardShortcut(.cancelAction) tidak aktif.
        .onExitCommand { dismiss() }
    }

    private func actionButton(_ icon: String,
                              _ title: String,
                              _ subtitle: String?,
                              destructive: Bool,
                              compact: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(destructive ? .red : .primary)
                    .frame(width: 22)
                if let subtitle {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(destructive ? .red : .primary)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(title)
                        .font(.system(size: 13, weight: compact ? .regular : .semibold))
                        .foregroundColor(.primary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 7 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Tanpa stroke: outline abu-abu di sekitar tombol merah terlihat
            // seperti artefak, bukan affordance.
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(compact ? Color.clear : (destructive ? Color.red.opacity(0.10) : Color.primary.opacity(0.04)))
            )
        }
        .buttonStyle(.plain)
        .noFocusRing()
        .accessibilityLabel(title)
    }
}