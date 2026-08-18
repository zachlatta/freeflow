import Darwin
import Foundation

enum SpotlightAttributes {
    static let hashAttribute = "com.flowarchive.hash"
    static let userTagsAttribute = "com.apple.metadata:_kMDItemUserTags"
    static let keywordsAttribute = "com.apple.metadata:kMDItemKeywords"

    static func apply(to urls: [URL], tags: [String], hash: String) {
        let finderTags = tags.map { "\($0)\n0" }
        for url in urls {
            writePlistAttribute(userTagsAttribute, value: finderTags, on: url)
            writePlistAttribute(keywordsAttribute, value: tags, on: url)
            setHash(hash, on: url)
        }
    }

    static func setHash(_ hash: String, on url: URL) {
        let bytes = Array(hash.utf8)
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = setxattr(url.path, hashAttribute, base, buffer.count, 0, 0)
        }
    }

    private static func writePlistAttribute(_ name: String, value: [String], on url: URL) {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: value,
            format: .binary,
            options: 0
        ) else { return }
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = setxattr(url.path, name, base, buffer.count, 0, 0)
        }
    }
}
