import SwiftUI

@main
struct GettoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var queue = QueueManager.shared
    @StateObject private var listVM = DownloadListViewModel.shared
    @StateObject private var settingsVM = SettingsViewModel()
    @State private var showAdd = false
    @State private var detailVisible = true
    @State private var showFirstRun = false
    @State private var clearedInitialFocus = false
    @AppStorage("getto.appearance") private var appearance: String = "system"

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(selection: $listVM.selection, queue: queue)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 270)
            } content: {
                ZStack {
                    AppBackground()
                    DownloadListView(queue: queue, vm: listVM, selectedId: $listVM.selectedId, detailVisible: $detailVisible)
                }
                .navigationSplitViewColumnWidth(min: 300, ideal: 360)
            } detail: {
                ZStack {
                    if detailVisible { AppBackground() }
                    if detailVisible {
                        DetailPanel(item: queue.items.first(where: { $0.id == listVM.selectedId }), queue: queue, showAdd: $showAdd)
                            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddDownloadSheet(queue: queue) }
            .onOpenURL { handleURL($0) }
            .onDrop(of: [.fileURL, .plainText, .url], isTargeted: nil) { providers in
                handleDrop(providers: providers)
                return true
            }
            .onReceive(NotificationCenter.default.publisher(for: .gettoOpenAddSheet)) { _ in showAdd = true }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                // Jangan autofocus kolom cari saat launch: aktif hanya saat diklik.
                // Sekali saja (kembali dari app lain tidak boleh mencuri fokus).
                // (Space setelah klik kartu harus Quick Look, bukan mengetik.)
                // Dijeda 0,5 dtk karena AppKit menetapkan fokus awal SETELAH become-key.
                if !clearedInitialFocus {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if !clearedInitialFocus {
                            clearedInitialFocus = true
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                    }
                }
            }
            .onAppear {
                NotificationService.shared.requestAuthorization()
                if queue.settings.showFirstRunNotice {
                    showFirstRun = true
                    queue.settings.showFirstRunNotice = false
                }
                Task { await queue.start() }
                // Repair manifest native host bila path/ID berubah (tanpa
                // menimpa ID ekstensi yang sudah dipasang user).
                NativeHostInstaller.repairIfNeeded()
            }
            .alert(NSLocalizedString("firstrun.title", value: "Tanggung jawab unduhan", comment: ""), isPresented: $showFirstRun) {
                Button(NSLocalizedString("firstrun.ok", value: "Mengerti", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("firstrun.message", value: "Pastikan Anda memiliki hak untuk mengunduh konten dan mematuhi ketentuan layanan situs serta hukum hak cipta yang berlaku. Getto tidak menyertakan fitur melewati DRM dan tidak mengirim data ke pihak ketiga.", comment: ""))
            }
            .preferredColorScheme(appearanceScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Tambah Unduhan…") { showAdd = true }.keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu(NSLocalizedString("menu.downloads", value: "Unduhan", comment: "")) {
                Button(NSLocalizedString("menu.pauseAll", value: "Jeda Semua", comment: "")) { queue.pauseAll() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button(NSLocalizedString("menu.resumeAll", value: "Lanjutkan Semua", comment: "")) { queue.resumeAll() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Divider()
                Toggle(NSLocalizedString("slowmode", value: "Mode lambat (1 KB/s)", comment: ""), isOn: $queue.slowMode)
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
                Button(NSLocalizedString("menu.clearDone", value: "Hapus yang Selesai", comment: "")) { queue.clearCompleted() }
                Toggle("Tampilkan Panel Detail", isOn: $detailVisible).keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandGroup(after: .help) {
                Button("Tampilkan Log") { Logger.revealLog() }
            }
        }

        Settings {
            SettingsView(vm: settingsVM)
        }

        MenuBarExtra("Getto", systemImage: "arrow.down.circle") {
            MenuBarView(queue: queue)
        }
    }

    private var appearanceScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // MARK: - URL scheme getto://add?url=<encoded>

    private func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "getto" else {
            // magnet: atau file .torrent dari Finder
            if url.scheme?.lowercased() == "magnet" {
                queue.addLinks(url.absoluteString)
            } else if url.pathExtension.lowercased() == "torrent" {
                queue.addTorrentFile(url)
            }
            return
        }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let link = comps.queryItems?.first(where: { $0.name == "url" })?.value,
              !link.isEmpty else {
            // getto://add tanpa parameter → buka sheet tambah (clipboard autofill di sana)
            NotificationCenter.default.post(name: .gettoOpenAddSheet, object: nil)
            return
        }
        queue.addLinks(link, headers: QueueManager.headersFromScheme(comps))
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for p in providers {
            if p.hasItemConformingToTypeIdentifier("public.file-url") {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        if url.pathExtension.lowercased() == "torrent" {
                            queue.addTorrentFile(url)
                        } else {
                            queue.addLinks(url.absoluteString)
                        }
                    }
                }
            } else if p.hasItemConformingToTypeIdentifier("public.plain-text") {
                _ = p.loadObject(ofClass: String.self) { str, _ in
                    guard let str = str else { return }
                    DispatchQueue.main.async { queue.addLinks(str) }
                }
            }
        }
    }
}
