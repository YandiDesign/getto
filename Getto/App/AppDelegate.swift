import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Daftarkan handler AppleEvent untuk scheme getto: & magnet: (cadangan selain SwiftUI onOpenURL)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        // Space → Quick Look; Escape → tutup detail (via KeyHandler).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let vm = DownloadListViewModel.shared
            let item = QueueManager.shared.items.first(where: { $0.id == vm.selectedId })
            let responder = NSApp.keyWindow?.firstResponder
            let inText = (responder is NSTextView) || (responder is NSControl)
            let keyWindow = NSApp.keyWindow
            // Saat sheet tampil, keyWindow adalah jendela sheet itu sendiri,
            // jadi harus dicek sheetParent-nya juga (hanya attachedSheet tidak
            // cukup — kalau tidak, Esc dianggap untuk list dan isinya hilang).
            let sheetOpen = (keyWindow?.attachedSheet != nil) || (keyWindow?.sheetParent != nil)
            let cmd = event.modifierFlags.contains(.command)
            // ⌘A saat mode pilih → pilih semua yang terlihat di daftar.
            if vm.selectionMode, cmd, event.keyCode == 0, !event.modifierFlags.contains(.option),
               !sheetOpen {
                let list = vm.filtered(QueueManager.shared.items)
                vm.setAllChecked(!vm.allChecked(in: list), in: list)
                return nil
            }
            let action = KeyHandler.resolve(
                keyCode: event.keyCode,
                modifiersEmpty: event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                characters: event.charactersIgnoringModifiers,
                inTextOrControl: inText,
                searchEmpty: vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty,
                sheetOpen: sheetOpen,
                hasSelection: vm.selectionMode || vm.selectedId != nil,
                previewable: QuickLookService.shouldPreview(item: item, firstResponder: responder)
            )
            switch action {
            case .none:
                return event
            case .clearSelection:
                if vm.selectionMode {
                    vm.exitSelectionMode()
                } else {
                    vm.selectedId = nil
                }
                return nil
            case .quickLook:
                if let item = item,
                   QuickLookService.shared.toggle(urls: [URL(fileURLWithPath: item.destinationPath)]) { return nil }
                return event
            }
        }
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let str = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: str) else { return }
        Logger.log("openURL: \(str)")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let scheme = url.scheme?.lowercased()
            if scheme == "magnet" {
                QueueManager.shared.addLinks(str)
            } else if scheme == "getto" {
                // getto://add?url=<encoded>&cookies=<..>&referer=<..> — teruskan
                // ke antrean beserta header login dari browser.
                if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let link = comps.queryItems?.first(where: { $0.name == "url" })?.value,
                   !link.isEmpty {
                    QueueManager.shared.addLinks(link, headers: QueueManager.headersFromScheme(comps))
                } else {
                    // getto://add tanpa parameter → buka sheet tambah
                    NotificationCenter.default.post(name: .gettoOpenAddSheet, object: nil)
                }
            } else if url.pathExtension.lowercased() == "torrent" {
                QueueManager.shared.addTorrentFile(url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        QueueManager.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain { window.makeKeyAndOrderFront(nil) }
        }
        return true
    }
}
