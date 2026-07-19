import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Observable store for the per-app screenshot allowlist, persisted to `AppContextSource.appsKey`.
/// Uses `ObservableObject` (not `@Observable`) because the deployment target is macOS 13.
@MainActor
final class AppContextAllowlist: ObservableObject {
    /// The allowlisted bundle identifiers (persisted).
    @Published private(set) var bundleIDs: [String]

    /// Loads the persisted allowlist (empty by default).
    init() {
        bundleIDs = UserDefaults.standard.array(forKey: AppContextSource.appsKey) as? [String] ?? []
    }

    /// Adds bundle ids, skipping blanks and duplicates; persists only if something changed.
    func add(_ ids: [String]) {
        let existing = Set(bundleIDs)
        let fresh = ids.filter { !$0.isEmpty && !existing.contains($0) }
        guard !fresh.isEmpty else { return }
        bundleIDs.append(contentsOf: fresh)
        persist()
    }

    /// Removes a bundle id and persists.
    func remove(_ id: String) {
        bundleIDs.removeAll { $0 == id }
        persist()
    }

    /// Writes the allowlist back to `UserDefaults`.
    private func persist() {
        UserDefaults.standard.set(bundleIDs, forKey: AppContextSource.appsKey)
    }

    /// Opens the "Add app…" picker and adds the bundle ids of any chosen apps.
    func presentPicker() {
        // AppKit open panel rooted at /Applications, limited to .app bundles.
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        add(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }
}

/// Resolves and caches an app's display name + icon from its bundle id (for the chips).
@MainActor
enum AppContextAppInfo {
    private static var cache: [String: (name: String, icon: NSImage?)] = [:]

    /// Returns the app's display name (falls back to the bundle id) and icon. Resolved once per id.
    static func info(forBundleID id: String) -> (name: String, icon: NSImage?) {
        if let hit = cache[id] { return hit }
        // Resolve the app's URL once, then its Finder name and icon (AppKit).
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? id
        let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        let result = (name, icon)
        cache[id] = result
        return result
    }
}

/// The screenshot scope multiselector: two radio cards plus the per-app chips and "Add app…" picker.
/// Binds the scope to `AppContextSource.scopeKey` via `@AppStorage` and observes the allowlist store.
struct ScreenshotScopeSection: View {
    /// Persisted scope (`"all"` | `"specific"`), defaulting to `all`.
    @AppStorage(AppContextSource.scopeKey) private var scopeRaw: String = AppContextSource.Scope.all.rawValue
    /// The allowlist store, owned by this view.
    @StateObject private var allowlist = AppContextAllowlist()
    /// Reflects the parent `.disabled()` (true only in Screenshot mode) — used to grey out chip icons.
    @Environment(\.isEnabled) private var isEnabled

    /// Current scope from the persisted value.
    private var scope: AppContextSource.Scope { AppContextSource.Scope(rawValue: scopeRaw) ?? .all }

    /// Header + the two scope options, plus the app chips when `specific`.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screenshot scope")
                .font(.caption.weight(.semibold))
            scopeOption(.all, title: "Send screenshot to all apps", subtitle: "Every app takes a screenshot.")
            scopeOption(.specific, title: "Only specific apps", subtitle: "Other apps use App summary instead.")
            if scope == .specific {
                specificAppsEditor
            }
        }
    }

    /// One selectable scope row in the app's radio-row style (checkmark + blue accent when selected).
    private func scopeOption(_ option: AppContextSource.Scope, title: String, subtitle: String) -> some View {
        let selected = scope == option
        return Button {
            scopeRaw = option.rawValue
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Read the row as one element to VoiceOver, with its selected state.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The app chips (or an empty-state line) plus the dashed "Add app…" button.
    private var specificAppsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allowlist.bundleIDs.isEmpty {
                Text("No apps added yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(allowlist.bundleIDs, id: \.self) { id in
                    chip(for: id)
                }
                addButton
            }
        }
    }

    /// A removable app chip: icon + name + ✕.
    private func chip(for id: String) -> some View {
        let info = AppContextAppInfo.info(forBundleID: id)
        return HStack(spacing: 6) {
            if let icon = info.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    // Desaturate when the screenshot block is disabled, so the icon dims like the text.
                    .grayscale(isEnabled ? 0 : 1)
            }
            Text(info.name)
                .font(.caption)
            Button {
                allowlist.remove(id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Remove \(info.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
    }

    /// The dashed "Add app…" button that opens the picker.
    private var addButton: some View {
        Button {
            allowlist.presentPicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("Add app…")
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add app")
    }
}
