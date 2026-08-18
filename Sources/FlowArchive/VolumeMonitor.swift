import AppKit
import Foundation

final class VolumeMonitor {
    var onMount: ((URL) -> Void)?
    var onUnmount: ((URL) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        let center = workspace.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = Self.volumeURL(from: notification) else { return }
            self?.onMount?(url)
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = Self.volumeURL(from: notification) else { return }
            self?.onUnmount?(url)
        })
    }

    func stop() {
        for observer in observers {
            workspace.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func mountedVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeNameKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.filter { url in
            url.path.hasPrefix("/Volumes/")
        }
    }

    func scanExisting() {
        for url in mountedVolumes() {
            onMount?(url)
        }
    }

    static func volumeUUID(for url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }

    static func volumeName(for url: URL) -> String {
        (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
            ?? url.lastPathComponent
    }

    private static func volumeURL(from notification: Notification) -> URL? {
        if let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
            return url
        }
        if let path = notification.userInfo?["NSDevicePath"] as? String {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
