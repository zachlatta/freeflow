import Combine
import Foundation

final class ArchiveSettings: ObservableObject {
    static let enabledKey = "flowarchive_enabled"
    static let providerKey = "flowarchive_destination_provider"
    static let bookmarkKey = "flowarchive_destination_bookmark"
    static let extraVolumeNamesKey = "flowarchive_extra_volume_names"
    static let confirmedVolumeUUIDKey = "flowarchive_confirmed_volume_uuid"
    static let extensionsKey = "flowarchive_audio_extensions"
    static let rulesKey = "flowarchive_folder_rules"
    static let promptKey = "flowarchive_organizer_prompt"
    static let dropFolderEnabledKey = "flowarchive_drop_folder_enabled"
    static let timeoutKey = "flowarchive_transcription_timeout_seconds"

    static let defaultExtensions = ["mp3", "m4a", "wav", "mp4", "aac"]
    static let defaultTimeoutSeconds: TimeInterval = 300

    static let defaultOrganizerPrompt = """
    Analyze this raw audio transcript. Step 1: Generate a concise, descriptive, 3-to-5 word filename using kebab-case (e.g., product-launch-strategy). Step 2: Extract a 3-bullet executive summary. Step 3: Identify relevant categorization tags.
    Return JSON only with keys filename (string), summary (array of 3 strings), and tags (array of lowercase strings). No markdown fences, no commentary.
    """

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    @Published var provider: CloudProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey) }
    }

    @Published var extraVolumeNames: String {
        didSet { UserDefaults.standard.set(extraVolumeNames, forKey: Self.extraVolumeNamesKey) }
    }

    @Published var confirmedVolumeUUID: String {
        didSet { UserDefaults.standard.set(confirmedVolumeUUID, forKey: Self.confirmedVolumeUUIDKey) }
    }

    @Published var audioExtensions: String {
        didSet { UserDefaults.standard.set(audioExtensions, forKey: Self.extensionsKey) }
    }

    @Published var folderRules: [FolderRule] {
        didSet {
            if let data = try? JSONEncoder().encode(folderRules) {
                UserDefaults.standard.set(data, forKey: Self.rulesKey)
            }
        }
    }

    @Published var organizerPrompt: String {
        didSet { UserDefaults.standard.set(organizerPrompt, forKey: Self.promptKey) }
    }

    @Published var dropFolderEnabled: Bool {
        didSet { UserDefaults.standard.set(dropFolderEnabled, forKey: Self.dropFolderEnabledKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.enabledKey) == nil {
            self.enabled = true
        } else {
            self.enabled = defaults.bool(forKey: Self.enabledKey)
        }

        if let raw = defaults.string(forKey: Self.providerKey),
           let stored = CloudProvider(rawValue: raw) {
            self.provider = stored
        } else if FileManager.default.ubiquityIdentityToken != nil {
            self.provider = .icloud
        } else {
            self.provider = .local
        }

        self.extraVolumeNames = defaults.string(forKey: Self.extraVolumeNamesKey) ?? ""
        self.confirmedVolumeUUID = defaults.string(forKey: Self.confirmedVolumeUUIDKey) ?? ""
        self.audioExtensions = defaults.string(forKey: Self.extensionsKey)
            ?? Self.defaultExtensions.joined(separator: ", ")
        if let data = defaults.data(forKey: Self.rulesKey),
           let rules = try? JSONDecoder().decode([FolderRule].self, from: data) {
            self.folderRules = rules
        } else {
            self.folderRules = []
        }
        self.organizerPrompt = defaults.string(forKey: Self.promptKey) ?? Self.defaultOrganizerPrompt
        if defaults.object(forKey: Self.dropFolderEnabledKey) == nil {
            self.dropFolderEnabled = true
        } else {
            self.dropFolderEnabled = defaults.bool(forKey: Self.dropFolderEnabledKey)
        }
    }

    var extraVolumeNameList: [String] {
        extraVolumeNames
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var extensionList: [String] {
        audioExtensions
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }

    var transcriptionTimeoutSeconds: TimeInterval {
        let override = defaults.double(forKey: Self.timeoutKey)
        return override > 0 ? override : Self.defaultTimeoutSeconds
    }

    func bookmarkData() -> Data? {
        defaults.data(forKey: Self.bookmarkKey)
    }

    func saveBookmark(for url: URL) {
        let data = try? url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: Self.bookmarkKey)
    }

    func resolvedCustomURL() -> URL? {
        guard let data = bookmarkData() else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}
