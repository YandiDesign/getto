import Foundation
import UserNotifications
import AppKit

/// Notifikasi selesai/gagal dengan aksi "Tampilkan di Finder".
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error { Logger.log("notif auth: \(error)") }
            Logger.log("notif granted=\(granted)")
        }
    }

    func notifyCompleted(fileName: String, fileURL: URL?) {
        guard QueueManager.shared.settings.notifyCompleted else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notif.done.title", value: "Unduhan selesai", comment: "")
        content.body = fileName
        content.sound = .default
        if let fileURL = fileURL {
            content.userInfo = ["path": fileURL.path]
            let action = UNNotificationAction(identifier: "SHOW_IN_FINDER",
                                              title: NSLocalizedString("notif.showFinder", value: "Tampilkan di Finder", comment: ""),
                                              options: .foreground)
            let category = UNNotificationCategory(identifier: "DOWNLOAD_DONE", actions: [action], intentIdentifiers: [])
            UNUserNotificationCenter.current().setNotificationCategories([category])
            content.categoryIdentifier = "DOWNLOAD_DONE"
        }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
        NSApp.dockTile.badgeLabel = nil
        NSApp.requestUserAttention(.informationalRequest)
    }

    func notifyFailed(fileName: String, reason: String) {
        guard QueueManager.shared.settings.notifyFailed else { return }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notif.fail.title", value: "Unduhan gagal", comment: "")
        content.body = "\(fileName) — \(reason)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Hitung mundur shutdown (selalu dikirim — penting untuk keselamatan).
    func notifyShutdownCountdown() {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notif.shutdown.title", value: "Semua unduhan selesai", comment: "")
        content.body = NSLocalizedString("notif.shutdown.body", value: "Komputer akan dimatikan dalam 60 detik. Tambahkan unduhan baru untuk membatalkan.", comment: "")
        content.sound = .default
        let req = UNNotificationRequest(identifier: "getto-shutdown", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Shutdown gagal (biasanya belum ada izin Aksesibilitas).
    func notifyShutdownFailed() {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notif.shutdownfail.title", value: "Gagal mematikan komputer", comment: "")
        content.body = NSLocalizedString("notif.shutdownfail.body", value: "Beri izin Aksesibilitas untuk Getto di Pengaturan Sistem → Privasi & Keamanan → Aksesibilitas, lalu coba lagi.", comment: "")
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "SHOW_IN_FINDER",
           let path = response.notification.request.content.userInfo["path"] as? String {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
