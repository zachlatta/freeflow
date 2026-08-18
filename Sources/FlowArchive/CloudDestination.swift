import Foundation

enum CloudProvider: String, Codable, CaseIterable, Identifiable {
    case icloud
    case gdrive
    case idrive
    case local
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icloud: return "iCloud Drive"
        case .gdrive: return "Google Drive"
        case .idrive: return "IDrive"
        case .local: return "This Mac only"
        case .custom: return "Choose folder…"
        }
    }

    var shortLabel: String {
        switch self {
        case .icloud: return "iCloud"
        case .gdrive: return "Google Drive"
        case .idrive: return "IDrive"
        case .local: return "Local"
        case .custom: return "Custom"
        }
    }
}

struct CloudDestinationOption: Equatable {
    var provider: CloudProvider
    var root: URL?
    var available: Bool
    var hint: String?
}

enum CloudDestination {
    static func iCloudDriveRoot(
        home: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let url = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Mobile Documents")
            .appendingPathComponent("com~apple~CloudDocs")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    static func googleDriveRoots(
        home: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let cloudStorage = home
            .appendingPathComponent("Library")
            .appendingPathComponent("CloudStorage")
        guard let items = try? fileManager.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return items.compactMap { drive in
            guard drive.lastPathComponent.hasPrefix("GoogleDrive-") else { return nil }
            let myDrive = drive.appendingPathComponent("My Drive")
            if fileManager.fileExists(atPath: myDrive.path) { return myDrive }
            return drive
        }
    }

    static func iDriveRoots(
        home: URL,
        volumes: [URL] = [],
        fileManager: FileManager = .default
    ) -> [URL] {
        var roots: [URL] = []
        let homeCandidates = ["IDrive", "IDrive Sync", "iDrive", "IDriveSync"]
        for name in homeCandidates {
            let url = home.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                roots.append(url)
            }
        }

        let cloudStorage = home
            .appendingPathComponent("Library")
            .appendingPathComponent("CloudStorage")
        if let items = try? fileManager.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for item in items where item.lastPathComponent.localizedCaseInsensitiveContains("idrive") {
                roots.append(item)
            }
        }

        for volume in volumes where volume.lastPathComponent.localizedCaseInsensitiveContains("idrive") {
            roots.append(volume)
        }

        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }
    }

    static func isIDriveAppInstalled(fileManager: FileManager = .default) -> Bool {
        let apps = [
            "/Applications/IDrive.app",
            "/Applications/IDrive Monitor.app",
            "/Applications/IDriveSync.app"
        ]
        return apps.contains { fileManager.fileExists(atPath: $0) }
    }

    static func documentsRoot(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    }

    static func options(
        home: URL,
        volumes: [URL] = [],
        fileManager: FileManager = .default
    ) -> [CloudDestinationOption] {
        let icloud = iCloudDriveRoot(home: home, fileManager: fileManager)
        let gdrive = googleDriveRoots(home: home, fileManager: fileManager).first
        let idrive = iDriveRoots(home: home, volumes: volumes, fileManager: fileManager).first
        let idriveInstalled = isIDriveAppInstalled(fileManager: fileManager)

        return [
            CloudDestinationOption(
                provider: .icloud,
                root: icloud,
                available: icloud != nil,
                hint: icloud == nil ? "iCloud Drive is not available on this Mac." : nil
            ),
            CloudDestinationOption(
                provider: .gdrive,
                root: gdrive,
                available: gdrive != nil,
                hint: gdrive == nil ? "Install Google Drive for Desktop, then reopen Settings." : nil
            ),
            CloudDestinationOption(
                provider: .idrive,
                root: idrive,
                available: idrive != nil || idriveInstalled,
                hint: idrive == nil
                    ? (idriveInstalled
                        ? "Choose your IDrive sync folder."
                        : "Install IDrive Sync, or choose its folder.")
                    : nil
            ),
            CloudDestinationOption(
                provider: .local,
                root: documentsRoot(fileManager: fileManager),
                available: true,
                hint: nil
            ),
            CloudDestinationOption(
                provider: .custom,
                root: nil,
                available: true,
                hint: nil
            )
        ]
    }

    static func defaultProvider(from options: [CloudDestinationOption]) -> CloudProvider {
        if options.contains(where: { $0.provider == .icloud && $0.available && $0.root != nil }) {
            return .icloud
        }
        if options.contains(where: { $0.provider == .gdrive && $0.available && $0.root != nil }) {
            return .gdrive
        }
        if options.contains(where: { $0.provider == .idrive && $0.root != nil }) {
            return .idrive
        }
        return .local
    }
}
