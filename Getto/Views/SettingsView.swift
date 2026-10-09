import SwiftUI

private func tr(_ key: String, _ fallback: String) -> String {
    NSLocalizedString(key, value: fallback, comment: "")
}

/// Jendela Pengaturan bergaya tab toolbar (macOS 13: TabView).
struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var extensionID: String = NativeHostInstaller.placeholderID
    @AppStorage("getto.appearance") private var appearance: String = "system"
    @AppStorage("getto.language") private var language: String = "system"
    @State private var showRestartHint = false

    var body: some View {
        TabView {
            generalTab.tabItem { Label(tr("settings.tab.general", "Umum"), systemImage: "gear") }.tag(0)
            downloadsTab.tabItem { Label(tr("settings.tab.downloads", "Unduhan"), systemImage: "arrow.down.circle") }.tag(1)
            videoTab.tabItem { Label(tr("settings.tab.video", "Video"), systemImage: "play.rectangle") }.tag(2)
            torrentTab.tabItem { Label(tr("settings.tab.torrent", "Torrent"), systemImage: "arrow.2.circlepath") }.tag(3)
            networkTab.tabItem { Label(tr("settings.tab.network", "Jaringan"), systemImage: "network") }.tag(4)
            browserTab.tabItem { Label(tr("settings.tab.browser", "Browser"), systemImage: "globe") }.tag(5)
            advancedTab.tabItem { Label(tr("settings.tab.advanced", "Lanjutan"), systemImage: "wrench") }.tag(6)
        }
        .frame(minWidth: 540, minHeight: 420)
        .padding()
    }

    private var generalTab: some View {
        Form {
            LabeledContent(tr("settings.downloadDir", "Folder unduhan")) {
                HStack {
                    Text(vm.settings.downloadDirectory).font(.caption).lineLimit(1).truncationMode(.middle)
                    Button(tr("settings.choose", "Pilih…")) { chooseDownloadDir() }
                }
            }
            Toggle(tr("settings.firstRunNotice", "Tampilkan catatan tanggung jawab saat pertama dibuka"), isOn: $vm.settings.showFirstRunNotice)
            Picker(tr("settings.appearance", "Tampilan"), selection: $appearance) {
                Text(tr("settings.appearance.system", "Mengikuti sistem")).tag("system")
                Text(tr("settings.appearance.light", "Terang")).tag("light")
                Text(tr("settings.appearance.dark", "Gelap")).tag("dark")
            }
            Picker(tr("settings.language", "Bahasa"), selection: $language) {
                Text(tr("settings.language.system", "Mengikuti sistem")).tag("system")
                Text("Indonesia").tag("id")
                Text("English").tag("en")
            }
            .onChange(of: language) { _ in
                vm.applyLanguage(language)
                showRestartHint = true
            }
            if showRestartHint {
                HStack {
                    Text(tr("settings.language.restart", "Bahasa diterapkan setelah aplikasi dimulai ulang."))
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button(tr("settings.language.quitApply", "Keluar & Terapkan")) {
                        NSApp.terminate(nil)
                    }
                }
            }
            Toggle(tr("settings.notifyDone", "Notifikasi saat unduhan selesai"), isOn: $vm.settings.notifyCompleted)
            Toggle(tr("settings.notifyFail", "Notifikasi saat unduhan gagal"), isOn: $vm.settings.notifyFailed)
            Toggle(tr("settings.shutdown", "Matikan komputer saat semua unduhan selesai"), isOn: $vm.settings.shutdownWhenDone)
            Text(tr("settings.shutdownNote", "Komputer dimatikan 60 detik setelah selesai (bisa dibatalkan dengan menambah unduhan). Butuh izin Aksesibilitas saat pertama dipakai."))
                .font(.caption).foregroundColor(.secondary)
            Text(tr("settings.privacy", "Getto tidak mengirim data apa pun ke server pihak ketiga."))
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var downloadsTab: some View {
        Form {
            Stepper(String(format: tr("settings.concurrent", "Unduhan bersamaan: %d"), vm.settings.maxConcurrentDownloads), value: $vm.settings.maxConcurrentDownloads, in: 1...10)
            Stepper(String(format: tr("settings.segments", "Segmen per file: %d"), vm.settings.segmentsPerDownload), value: $vm.settings.segmentsPerDownload, in: 1...16)
            HStack {
                Text(tr("settings.speedLimit", "Batas kecepatan global (KB/s, 0 = tanpa batas)"))
                TextField("0", value: $vm.settings.globalSpeedLimitKBps, formatter: NumberFormatter())
                    .frame(width: 80)
            }
            Picker(tr("settings.ifExists", "Jika file sudah ada"), selection: $vm.settings.duplicateBehavior) {
                Text(tr("settings.exists.rename", "Ganti nama")).tag("rename")
                Text(tr("settings.exists.overwrite", "Timpa")).tag("overwrite")
                Text(tr("settings.exists.skip", "Lewati")).tag("skip")
            }
        }
    }

    private var videoTab: some View {
        Form {
            Picker(tr("settings.defQuality", "Kualitas default"), selection: $vm.settings.defaultQuality) {
                ForEach(MediaQuality.allCases, id: \.self) { q in Text(q.label).tag(q) }
            }
            Picker(tr("settings.defContainer", "Format default"), selection: $vm.settings.defaultContainer) {
                ForEach(MediaVideoContainer.allCases, id: \.self) { c in Text(c.rawValue.uppercased()).tag(c) }
            }
            Picker(tr("settings.defCodec", "Codec video default"), selection: $vm.settings.defaultVideoCodec) {
                ForEach(MediaVideoCodec.allCases, id: \.self) { v in Text(v.label).tag(v) }
            }
            Picker(tr("settings.audioFormat", "Format audio"), selection: $vm.settings.defaultAudioFormat) {
                ForEach(MediaAudioFormat.allCases, id: \.self) { a in Text(a.rawValue.uppercased()).tag(a) }
            }
            Toggle(tr("settings.audioOnlyDefault", "Audio saja sebagai default"), isOn: $vm.settings.defaultAudioOnly)
            Picker(tr("settings.cookiesFromBrowser", "Cookie browser otomatis (video)"), selection: $vm.settings.cookiesFromBrowser) {
                Text(tr("settings.cookiesFromBrowser.off", "Mati")).tag("")
                Text("Chrome").tag("chrome")
                Text("Chromium").tag("chromium")
                Text("Brave").tag("brave")
                Text("Edge").tag("edge")
                Text("Firefox").tag("firefox")
                Text("Safari").tag("safari")
            }
            Text(tr("settings.cookiesFromBrowser.note", "Untuk link yang ditempel manual (tanpa lewat ekstensi). Butuh akses keychain sekali."))
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Button(tr("settings.updateEngine", "Perbarui mesin yt-dlp")) { vm.updateYtDlp() }
                Text(vm.ytDlpVersion).font(.caption).foregroundColor(.secondary)
            }
            .onAppear { vm.checkYtDlpVersion() }
        }
    }

    private var torrentTab: some View {
        Form {
            HStack {
                Text(tr("settings.inPort", "Port masuk"))
                TextField("port", value: $vm.settings.torrentPort, formatter: NumberFormatter()).frame(width: 80)
            }
            HStack {
                Text(tr("settings.dlLimit", "Batas unduh (KB/s, 0 = tanpa batas)"))
                TextField("0", value: $vm.settings.torrentDownloadLimitKBps, formatter: NumberFormatter()).frame(width: 80)
            }
            HStack {
                Text(tr("settings.ulLimit", "Batas unggah (KB/s, 0 = tanpa batas)"))
                TextField("0", value: $vm.settings.torrentUploadLimitKBps, formatter: NumberFormatter()).frame(width: 80)
            }
            Toggle("DHT", isOn: $vm.settings.torrentDHT)
            Toggle(tr("settings.pex", "Peer Exchange (PEX)"), isOn: $vm.settings.torrentPEX)
            Toggle(tr("settings.encryption", "Enkripsi"), isOn: $vm.settings.torrentEncryption)
            HStack {
                Text(tr("settings.seedRatio", "Batas rasio seeding"))
                TextField("1.0", value: $vm.settings.torrentSeedRatioLimit, formatter: NumberFormatter()).frame(width: 80)
            }
            Toggle(tr("settings.handleMagnet", "Tangani magnet link"), isOn: $vm.settings.handleMagnetLinks)
            Toggle(tr("settings.handleTorrent", "Tangani file .torrent"), isOn: $vm.settings.handleTorrentFiles)
        }
    }

    private var networkTab: some View {
        Form {
            TextField(tr("settings.cookies", "Cookie"), text: $vm.settings.cookies)
            HStack {
                TextField(tr("settings.username", "Username (basic auth)"), text: $vm.settings.httpUsername)
                SecureField(tr("settings.password", "Password"), text: $vm.settings.httpPassword)
            }
            Text(tr("settings.headersNote", "Header kustom per unduhan diisi lewat sheet Tambah → Lanjutan."))
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var browserTab: some View {
        Form {
            LabeledContent(tr("settings.extStatus", "Status ekstensi"), value: vm.nativeHostStatus)
            TextField(tr("settings.extID", "ID Ekstensi Chrome"), text: $extensionID).font(.caption).textSelection(.enabled)
            HStack {
                Button(tr("settings.install", "Pasang integrasi")) { vm.installNativeHost(extensionID: extensionID) }
                Button(tr("settings.openFolder", "Buka folder ekstensi")) {
                    let dir = Bundle.main.bundleURL.deletingLastPathComponent()
                    NSWorkspace.shared.open(dir)
                }
            }
            Text(tr("settings.browserHelp", "Pasang ekstensi: chrome://extensions → Developer mode → Load unpacked → pilih folder chrome-extension. Masukkan ID ekstensi ke kolom di atas, lalu klik Pasang integrasi."))
                .font(.caption).foregroundColor(.secondary)
        }
        .onAppear { vm.refreshNativeHostStatus() }
    }

    private var advancedTab: some View {
        Form {
            Button(tr("settings.showLog", "Tampilkan Log")) { Logger.revealLog() }
            Button(tr("settings.resetQueue", "Reset antrean (hapus semua)")) {
                QueueManager.shared.clearCompleted()
            }
            Text(tr("settings.sandboxNote", "Sandbox: nonaktif. Hardened Runtime: aktif. Binary pendukung ditandatangani di dalam bundle."))
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func chooseDownloadDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            vm.settings.downloadDirectory = url.path
        }
    }
}
