import SwiftUI
import UniformTypeIdentifiers

struct AddDownloadSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var queue: QueueManager
    @State private var linkText: String = ""
    @State private var showAdvanced = false
    @State private var customHeaders = ""
    @State private var cookies = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isVideoLink = false
    @State private var preview: MediaInfo?
    @State private var previewURL: String?
    @State private var previewError: String?
    @State private var loadingPreview = false
    @State private var previewTask: Task<Void, Never>?
    @State private var mediaOptions = MediaOptions()
    @State private var subtitleLangs = ""

    var body: some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString("add.title", value: "Tambah Unduhan", comment: ""))
                .font(.system(size: 16, weight: .bold, design: .rounded))

            // Kotak link FIXED agar tombol selalu terlihat (tidak melar)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                TextEditor(text: $linkText)
                    .font(.system(size: 12.5))
                    .frame(height: 64)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                if linkText.isEmpty {
                    Text(NSLocalizedString("add.linkPlaceholder", value: "Tempel satu link per baris…", comment: ""))
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 76)
            .accessibilityLabel(NSLocalizedString("add.linkLabel", value: "Kolom link", comment: ""))
            .onChange(of: linkText) { _ in detectVideo() }

            if loadingPreview {
                ProgressView(NSLocalizedString("add.loadingPreview", value: "Memuat pratinjau…", comment: ""))
                    .font(.callout)
            }
            if let err = previewError, !loadingPreview {
                Text(err).font(.caption).foregroundColor(.red).lineLimit(3)
            }
            if let p = preview {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: p.thumbnailURL ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 168, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                        if let ch = p.channel {
                            Text(ch).font(.system(size: 12.5)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Text(p.durationString).font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .glassCard(radius: 14)
            }

            // Pilihan kualitas/format — tampil selama link adalah video,
            // walau pratinjau gagal (opsi tidak bergantung pada pratinjau).
            if isVideoLink {
                VStack(spacing: 8) {
                    optionRow(NSLocalizedString("add.quality", value: "Kualitas", comment: "")) {
                        Picker("", selection: $mediaOptions.quality) {
                            ForEach(MediaQuality.allCases, id: \.self) { q in Text(q.label).tag(q) }
                        }.labelsHidden()
                    }
                    optionRow(NSLocalizedString("add.format", value: "Format", comment: "")) {
                        Picker("", selection: $mediaOptions.container) {
                            ForEach(MediaVideoContainer.allCases, id: \.self) { c in Text(c.rawValue.uppercased()).tag(c) }
                        }.labelsHidden().disabled(mediaOptions.audioOnly)
                    }
                    if !mediaOptions.audioOnly {
                        optionRow(NSLocalizedString("add.codec", value: "Codec", comment: "")) {
                            Picker("", selection: $mediaOptions.videoCodec) {
                                ForEach(MediaVideoCodec.allCases, id: \.self) { v in Text(v.label).tag(v) }
                            }.labelsHidden()
                        }
                        .help(NSLocalizedString("add.codecHelp", value: "H.264 bisa diputar dan di-Quick Look di Mac Intel; Otomatis bisa menghasilkan AV1/VP9", comment: ""))
                    }
                    HStack {
                        Toggle(NSLocalizedString("add.audioOnly", value: "Audio saja", comment: ""), isOn: $mediaOptions.audioOnly)
                        Spacer()
                        if mediaOptions.audioOnly {
                            Picker("", selection: $mediaOptions.audioFormat) {
                                ForEach(MediaAudioFormat.allCases, id: \.self) { a in Text(a.rawValue.uppercased()).tag(a) }
                            }.labelsHidden()
                        }
                    }
                    .font(.callout)
                    HStack {
                        Text(NSLocalizedString("add.subtitle", value: "Subtitle", comment: ""))
                            .font(.callout)
                            .frame(width: 90, alignment: .leading)
                        TextField(NSLocalizedString("add.subtitleHint", value: "mis. id,en", comment: ""), text: $subtitleLangs)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                        Toggle(NSLocalizedString("add.embed", value: "Embed", comment: ""), isOn: $mediaOptions.embedSubtitle)
                            .font(.callout)
                    }
                }
            }

            DisclosureGroup(NSLocalizedString("add.advanced", value: "Lanjutan", comment: ""), isExpanded: $showAdvanced) {
                TextField(NSLocalizedString("add.headersHint", value: "Header kustom (Key: Value per baris)", comment: ""), text: $customHeaders)
                TextField(NSLocalizedString("add.cookies", value: "Cookie", comment: ""), text: $cookies)
                HStack {
                    TextField(NSLocalizedString("add.username", value: "Username", comment: ""), text: $username)
                    SecureField(NSLocalizedString("add.password", value: "Password", comment: ""), text: $password)
                }
            }
            .font(.callout)

            HStack {
                Spacer()
Button(NSLocalizedString("common.cancel", value: "Batal", comment: "")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .noFocusRing()
                Button(action: add) {
                    Text(NSLocalizedString("common.download", value: "Unduh", comment: ""))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(
                            (linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue).gradient,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .noFocusRing()
                .buttonStyle(.plain)
                .noFocusRing()
                .keyboardShortcut(.defaultAction)
                .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(NSLocalizedString("common.download", value: "Unduh", comment: ""))
            }
        }
        .padding(20)
        .frame(minWidth: 540, idealWidth: 580)
        .onAppear {
            // Autofill dari clipboard saat sheet dibuka
            let urls = ClipboardService.urlsInClipboard()
            if !urls.isEmpty && linkText.isEmpty {
                linkText = urls.joined(separator: "\n")
                detectVideo()
            }
        }
    }

    private func optionRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.callout)
                .frame(width: 90, alignment: .leading)
            content()
            Spacer()
        }
    }

    private func detectVideo() {
        // Batalkan request lama: tiap ketikan memicu detectVideo, tanpa cancel
        // request usang menumpuk, me-rate-limit YouTube, dan bisa menimpa hasil baru.
        previewTask?.cancel()
        let first = linkText.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        isVideoLink = ClipboardService.isVideoURL(first)
        guard isVideoLink, !first.isEmpty else {
            preview = nil; previewURL = nil; previewError = nil; loadingPreview = false
            return
        }
        previewURL = first
        loadingPreview = true
        previewError = nil
        previewTask = Task {
            // Debounce: tunggu pengguna selesai mengetik sebelum memanggil yt-dlp.
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                let info = try await MediaEngine.shared.fetchPreview(urlString: first)
                await MainActor.run {
                    guard previewURL == first else { return } // hasil usang, abaikan
                    preview = info; loadingPreview = false
                }
            } catch {
                await MainActor.run {
                    guard previewURL == first else { return } // hasil usang, abaikan
                    loadingPreview = false; preview = nil
                    previewError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func add() {
        // Kumpulkan header Lanjutan: baris "Key: Value" + Cookie + basic auth.
        var headers: [String: String] = [:]
        for line in customHeaders.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty { headers[parts[0]] = parts[1] }
        }
        let cookieText = cookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cookieText.isEmpty {
            headers["Cookie"] = [headers["Cookie"], cookieText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "; ")
        }
        if !username.isEmpty {
            let cred = Data("\(username):\(password)".utf8).base64EncodedString()
            headers["Authorization"] = "Basic \(cred)"
        }
        // Terapkan opsi media ke default untuk unduhan video kali ini
        if isVideoLink {
            queue.settings.defaultQuality = mediaOptions.quality
            queue.settings.defaultContainer = mediaOptions.container
            queue.settings.defaultVideoCodec = mediaOptions.videoCodec
            queue.settings.defaultAudioFormat = mediaOptions.audioFormat
            queue.settings.defaultAudioOnly = mediaOptions.audioOnly
            queue.settings.defaultSubtitleLangs = subtitleLangs
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            queue.settings.defaultEmbedSubtitle = mediaOptions.embedSubtitle
        }
        let created = queue.addLinks(linkText, headers: headers)
        // Ganti nama placeholder ("watch.mp4") dengan judul asli pratinjau — hanya untuk item baru.
        if let info = preview, let first = created.first(where: { $0.status == .queued }) {
            let ext = mediaOptions.audioOnly ? mediaOptions.audioFormat.rawValue : mediaOptions.container.rawValue
            queue.applyMediaTitle(id: first.id, title: info.title, ext: ext)
        }
        dismiss()
    }
}

struct TorrentFilePickerSheet: View {
    @Environment(\.dismiss) var dismiss
    let files: [TorrentFileEntry]
    @State private var selected: Set<Int>
    var onDone: ([Int]) -> Void

    init(files: [TorrentFileEntry], onDone: @escaping ([Int]) -> Void) {
        self.files = files
        _selected = State(initialValue: Set(files.filter { $0.selected }.map { $0.index }))
        self.onDone = onDone
    }

    var body: some View {
        VStack {
            Text(NSLocalizedString("torrent.pickTitle", value: "Pilih file dalam torrent", comment: "")).font(.headline)
            List(files) { f in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { selected.contains(f.index) },
                        set: { on in if on { selected.insert(f.index) } else { selected.remove(f.index) } }
                    )).labelsHidden()
                    Text((f.path as NSString).lastPathComponent).lineLimit(1)
                    Spacer()
                    Text(formatBytes(f.length)).font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 200)
            HStack {
                Spacer()
                Button(NSLocalizedString("common.cancel", value: "Batal", comment: "")) { dismiss() }
                    .noFocusRing()
                Button(NSLocalizedString("common.download", value: "Unduh", comment: "")) { onDone(Array(selected).sorted()); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
                    .noFocusRing()
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 340)
    }
}
