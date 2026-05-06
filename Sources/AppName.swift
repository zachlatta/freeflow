import Foundation

enum AppName {
    static let displayName: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FreeFlow"
}
