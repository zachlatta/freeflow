import CryptoKit
import Foundation

// MARK: - CRC32

// Standard reflected CRC32 with polynomial 0xEDB88320.
private let crc32Table: [UInt32] = (0..<256).map { i -> UInt32 in
    var crc = UInt32(i)
    for _ in 0..<8 {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
    }
    return crc
}

func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
        crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(byte)) & 0xFF)]
    }
    return crc ^ 0xFFFF_FFFF
}

// MARK: - SigV4

enum AWSSignature {
    private static let algorithm = "AWS4-HMAC-SHA256"

    /// Sign an AWS request and return the headers that must be merged into the
    /// outgoing request (`Authorization`, `x-amz-date`, `x-amz-content-sha256`).
    ///
    /// - Parameters:
    ///   - method: HTTP method in uppercase, e.g. "POST"
    ///   - url: Full request URL (host, path, query parsed from it)
    ///   - headers: Headers already planned for the request (not including
    ///     `Authorization` or `x-amz-date` — those are returned by this function).
    ///     Host should NOT be included; it is derived from `url`.
    ///   - body: Complete request body bytes
    ///   - service: AWS service name, e.g. `"bedrock"` or `"transcribe"`
    ///   - region: AWS region, e.g. `"us-east-1"`
    ///   - accessKeyId: AWS access key ID
    ///   - secretAccessKey: AWS secret access key
    ///   - date: Signing date (defaults to now; injectable for tests)
    static func sign(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data,
        service: String,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String? = nil,
        date: Date = Date()
    ) -> [String: String] {
        let amzDate = iso8601Compact(date)
        let datestamp = iso8601Date(date)

        // Normalize all header keys to lowercase for signing.
        let payloadHash = sha256Hex(body)
        var normalizedHeaders: [String: String] = [:]
        for (k, v) in headers { normalizedHeaders[k.lowercased()] = v }
        normalizedHeaders["host"] = url.host ?? ""
        normalizedHeaders["x-amz-date"] = amzDate
        normalizedHeaders["x-amz-content-sha256"] = payloadHash
        if let token = sessionToken, !token.isEmpty {
            normalizedHeaders["x-amz-security-token"] = token
        }

        let sortedKeys = normalizedHeaders.keys.sorted()
        let canonicalHeaders = sortedKeys
            .map { k in "\(k):\(normalizedHeaders[k]!.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n") + "\n"
        let signedHeaders = sortedKeys.joined(separator: ";")

        let canonicalURI = canonicalPath(url)
        let canonicalQueryString = canonicalQuery(url)

        let canonicalRequest = [
            method.uppercased(),
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let credentialScope = "\(datestamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(
            secretKey: secretAccessKey,
            date: datestamp,
            region: region,
            service: service
        )
        let signature = hmacSHA256Hex(key: signingKey, data: Data(stringToSign.utf8))

        let authorization = "\(algorithm) Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var result: [String: String] = [
            "Authorization": authorization,
            "x-amz-date": amzDate,
            "x-amz-content-sha256": payloadHash
        ]
        if let token = sessionToken, !token.isEmpty {
            result["x-amz-security-token"] = token
        }
        return result
    }

    // MARK: - Private helpers

    private static func deriveSigningKey(
        secretKey: String,
        date: String,
        region: String,
        service: String
    ) -> [UInt8] {
        let kDate    = hmacSHA256(key: Array("AWS4\(secretKey)".utf8), data: Data(date.utf8))
        let kRegion  = hmacSHA256(key: kDate,    data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion,  data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        return kSigning
    }

    private static func hmacSHA256(key: [UInt8], data: Data) -> [UInt8] {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Array(mac)
    }

    private static func hmacSHA256Hex(key: [UInt8], data: Data) -> String {
        hmacSHA256(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalPath(_ url: URL) -> String {
        let path = url.path
        return path.isEmpty ? "/" : path
    }

    private static func canonicalQuery(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else {
            return ""
        }
        return items
            .map { ($0.name, $0.value ?? "") }
            .sorted { $0.0 < $1.0 }
            .map { "\(rfc3986Encode($0.0))=\(rfc3986Encode($0.1))" }
            .joined(separator: "&")
    }

    private static func rfc3986Encode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    // MARK: - Date formatters

    private static let compactFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    static func iso8601Compact(_ date: Date) -> String { compactFormatter.string(from: date) }
    static func iso8601Date(_ date: Date) -> String { dateFormatter.string(from: date) }

    // MARK: - Extended sign returning signing key + signature bytes

    struct SignedRequest {
        let headers: [String: String]
        let signatureBytes: [UInt8]
        let signingKey: [UInt8]
        let amzDate: String
        let credentialScope: String
    }

    static func signRequest(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data,
        service: String,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String? = nil,
        date: Date = Date()
    ) -> SignedRequest {
        let amzDate = iso8601Compact(date)
        let datestamp = iso8601Date(date)

        let payloadHash = sha256Hex(body)
        var normalizedHeaders: [String: String] = [:]
        for (k, v) in headers { normalizedHeaders[k.lowercased()] = v }
        normalizedHeaders["host"] = url.host ?? ""
        normalizedHeaders["x-amz-date"] = amzDate
        normalizedHeaders["x-amz-content-sha256"] = payloadHash
        if let token = sessionToken, !token.isEmpty {
            normalizedHeaders["x-amz-security-token"] = token
        }

        let sortedKeys = normalizedHeaders.keys.sorted()
        let canonicalHeaders = sortedKeys
            .map { k in "\(k):\(normalizedHeaders[k]!.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n") + "\n"
        let signedHeaders = sortedKeys.joined(separator: ";")

        let canonicalRequest = [
            method.uppercased(),
            canonicalPath(url),
            canonicalQuery(url),
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let credentialScope = "\(datestamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(
            secretKey: secretAccessKey,
            date: datestamp,
            region: region,
            service: service
        )
        let signatureBytes = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8))
        let signatureHex = signatureBytes.map { String(format: "%02x", $0) }.joined()

        let authorization = "\(algorithm) Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signatureHex)"

        var resultHeaders: [String: String] = [
            "Authorization": authorization,
            "x-amz-date": amzDate,
            "x-amz-content-sha256": payloadHash
        ]
        if let token = sessionToken, !token.isEmpty {
            resultHeaders["x-amz-security-token"] = token
        }

        return SignedRequest(
            headers: resultHeaders,
            signatureBytes: signatureBytes,
            signingKey: signingKey,
            amzDate: amzDate,
            credentialScope: credentialScope
        )
    }

    // MARK: - Per-event-frame chunk signing

    /// Signs a single event stream frame payload.
    /// Returns the 32-byte HMAC chunk signature.
    static func signEventChunk(
        payload: Data,
        nonSigHeaderBytes: Data,
        priorSignature: [UInt8],
        signingKey: [UInt8],
        amzDate: String,
        credentialScope: String
    ) -> [UInt8] {
        let priorSigHex = priorSignature.map { String(format: "%02x", $0) }.joined()
        let stringToSign = "AWS4-HMAC-SHA256-PAYLOAD\n"
            + amzDate + "\n"
            + credentialScope + "\n"
            + priorSigHex + "\n"
            + sha256Hex(nonSigHeaderBytes) + "\n"
            + sha256Hex(payload)
        return hmacSHA256(key: signingKey, data: Data(stringToSign.utf8))
    }
}

// MARK: - Amazon Event Stream

/// Encodes and decodes Amazon Event Stream frames used by Transcribe streaming.
enum EventStream {

    // MARK: Header types

    enum HeaderValue {
        case string(String)       // type 7
        case bytes(Data)          // type 6
        case timestamp(Date)      // type 8 — int64 milliseconds since epoch, big-endian
    }

    // MARK: Encode

    /// Serialize headers only — used for chunk-signature hashing (no frame wrapper).
    static func serializeHeaders(_ headers: [(name: String, value: HeaderValue)]) -> Data {
        var data = Data()
        for h in headers {
            let nameBytes = Data(h.name.utf8)
            data.append(UInt8(nameBytes.count))
            data.append(contentsOf: nameBytes)
            switch h.value {
            case .string(let s):
                let valueBytes = Data(s.utf8)
                data.append(7)
                let len = UInt16(valueBytes.count)
                data.append(UInt8((len >> 8) & 0xFF))
                data.append(UInt8(len & 0xFF))
                data.append(contentsOf: valueBytes)
            case .bytes(let b):
                data.append(6)
                let len = UInt16(b.count)
                data.append(UInt8((len >> 8) & 0xFF))
                data.append(UInt8(len & 0xFF))
                data.append(contentsOf: b)
            case .timestamp(let t):
                data.append(8)
                let ms = Int64(t.timeIntervalSince1970 * 1000)
                data.appendBE64(ms)
            }
        }
        return data
    }

    /// Encode a single event frame.
    ///
    /// Frame layout (all integers big-endian):
    ///   [4] total byte length (includes all fields including itself and message CRC)
    ///   [4] headers byte length
    ///   [4] prelude CRC32 (of the preceding 8 bytes)
    ///   [?] headers
    ///   [?] payload
    ///   [4] message CRC32 (of all preceding bytes in the frame)
    static func encodeFrame(payload: Data, headers: [(name: String, value: HeaderValue)]) -> Data {
        let headersData = serializeHeaders(headers)
        let headersLen = UInt32(headersData.count)
        let totalLen = UInt32(16 + headersData.count + payload.count)

        var frame = Data()
        frame.appendBE32(totalLen)
        frame.appendBE32(headersLen)

        let preludeCRC = crc32(frame) // CRC of first 8 bytes
        frame.appendBE32(preludeCRC)

        frame.append(headersData)
        frame.append(payload)

        let messageCRC = crc32(frame)
        frame.appendBE32(messageCRC)

        return frame
    }

    /// Build and sign an audio event frame using the double-wrapped structure required by AWS.
    ///
    /// Structure:
    ///   inner frame = {`:message-type`, `:event-type`, `:content-type`} headers + PCM payload
    ///   outer frame = {`:date`, `:chunk-signature`} headers + inner frame as payload
    ///
    /// Returns the outer frame bytes and the new chunk signature (to use as priorSignature for next frame).
    static func signedAudioFrame(
        audio: Data,
        priorSignature: [UInt8],
        signingKey: [UInt8],
        credentialScope: String
    ) -> (frame: Data, signature: [UInt8]) {
        let now = Date()
        let frameAmzDate = AWSSignature.iso8601Compact(now)

        // Inner frame: event content headers + raw PCM
        let innerHeaders: [(name: String, value: HeaderValue)] = [
            (name: ":message-type", value: .string("event")),
            (name: ":event-type",   value: .string("AudioEvent")),
            (name: ":content-type", value: .string("application/octet-stream"))
        ]
        let innerFrame = encodeFrame(payload: audio, headers: innerHeaders)

        // nonSigHeaderBytes for signing = just the :date header
        let dateHeaders: [(name: String, value: HeaderValue)] = [
            (name: ":date", value: .timestamp(now))
        ]
        let nonSigHeaderBytes = serializeHeaders(dateHeaders)

        let sig = AWSSignature.signEventChunk(
            payload: innerFrame,
            nonSigHeaderBytes: nonSigHeaderBytes,
            priorSignature: priorSignature,
            signingKey: signingKey,
            amzDate: frameAmzDate,
            credentialScope: credentialScope
        )

        // Outer frame: {date, chunk-signature} headers + inner frame as payload
        let outerHeaders: [(name: String, value: HeaderValue)] = [
            (name: ":date",            value: .timestamp(now)),
            (name: ":chunk-signature", value: .bytes(Data(sig)))
        ]
        return (encodeFrame(payload: innerFrame, headers: outerHeaders), sig)
    }

    /// Build and sign the terminal "complete signal" frame.
    ///
    /// AWS requires the sequence: empty audio frame (signedAudioFrame with empty data)
    /// followed by this terminal frame, which is a signed outer frame with truly empty
    /// payload (not wrapped in an inner AudioEvent).
    static func signedTerminalFrame(
        priorSignature: [UInt8],
        signingKey: [UInt8],
        credentialScope: String
    ) -> Data {
        let now = Date()
        let frameAmzDate = AWSSignature.iso8601Compact(now)

        let dateHeaders: [(name: String, value: HeaderValue)] = [
            (name: ":date", value: .timestamp(now))
        ]
        let nonSigHeaderBytes = serializeHeaders(dateHeaders)

        // payload = truly empty (not an inner AudioEvent frame)
        let sig = AWSSignature.signEventChunk(
            payload: Data(),
            nonSigHeaderBytes: nonSigHeaderBytes,
            priorSignature: priorSignature,
            signingKey: signingKey,
            amzDate: frameAmzDate,
            credentialScope: credentialScope
        )

        let outerHeaders: [(name: String, value: HeaderValue)] = [
            (name: ":date",            value: .timestamp(now)),
            (name: ":chunk-signature", value: .bytes(Data(sig)))
        ]
        return encodeFrame(payload: Data(), headers: outerHeaders)
    }

    // MARK: Decode

    struct Frame {
        let headers: [String: String]
        let payload: Data
    }

    /// Parse all frames from a contiguous event-stream response body.
    static func decodeFrames(from data: Data) -> [Frame] {
        var frames: [Frame] = []
        var offset = 0

        while offset + 16 <= data.count {
            let totalLen = Int(readBE32(data, at: offset))
            guard totalLen >= 16, offset + totalLen <= data.count else { break }

            let headersLen = Int(readBE32(data, at: offset + 4))
            // Skip prelude CRC at offset+8

            var headers: [String: String] = [:]
            var hi = offset + 12
            let headersEnd = hi + headersLen
            while hi < headersEnd {
                guard hi < data.count else { break }
                let nameLen = Int(data[hi]); hi += 1
                guard hi + nameLen <= data.count else { break }
                let name = String(bytes: data[hi..<(hi + nameLen)], encoding: .utf8) ?? ""; hi += nameLen
                guard hi < data.count else { break }
                let valueType = data[hi]; hi += 1
                guard valueType == 7, hi + 2 <= data.count else { break }
                let valueLen = Int(readBE16(data, at: hi)); hi += 2
                guard hi + valueLen <= data.count else { break }
                let value = String(bytes: data[hi..<(hi + valueLen)], encoding: .utf8) ?? ""; hi += valueLen
                headers[name] = value
            }

            let payloadStart = offset + 12 + headersLen
            let payloadEnd   = offset + totalLen - 4 // exclude message CRC
            if payloadStart <= payloadEnd, payloadEnd <= data.count {
                frames.append(Frame(headers: headers, payload: data[payloadStart..<payloadEnd]))
            }
            offset += totalLen
        }

        return frames
    }

    // MARK: Private

    private static func readBE32(_ data: Data, at i: Int) -> UInt32 {
        (UInt32(data[i]) << 24) | (UInt32(data[i+1]) << 16) | (UInt32(data[i+2]) << 8) | UInt32(data[i+3])
    }

    private static func readBE16(_ data: Data, at i: Int) -> UInt16 {
        (UInt16(data[i]) << 8) | UInt16(data[i+1])
    }
}

// MARK: - Data helpers

extension Data {
    mutating func appendBE32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendBE64(_ value: Int64) {
        let u = UInt64(bitPattern: value)
        append(UInt8((u >> 56) & 0xFF))
        append(UInt8((u >> 48) & 0xFF))
        append(UInt8((u >> 40) & 0xFF))
        append(UInt8((u >> 32) & 0xFF))
        append(UInt8((u >> 24) & 0xFF))
        append(UInt8((u >> 16) & 0xFF))
        append(UInt8((u >> 8)  & 0xFF))
        append(UInt8(u         & 0xFF))
    }
}
