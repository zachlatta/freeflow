import Foundation

enum CredentialRecipeTests {
    private static let syntheticKey = "-synthetic '\"\\ $HOME \u{0060}printf synthetic\u{0060} $(printf fixture) café 🧪"

    private struct RecipeResult {
        let status: Int32
        let output: String
        let command: String
        let environment: [String: String]
        let sampledArguments: [String]
    }

    static func run() {
        do {
            try createsPrivateSettings()
            try createsPrivateDevelopmentSettings()
            try acceptsCompleteBoundedInput()
            try preservesExistingCredentials()
            try refusesInvalidSettings()
            try refusesCancelledOrInvalidInput()
            try refusesUnwritableDirectory()
            try keepsSecretOffCommandsAndOutput()
        } catch {
            fatalError("Credential recipe fixture failed: \(error)")
        }
    }

    private static func createsPrivateSettings() throws {
        try withFixture { directory, settings in
            let result = try runRecipe(home: directory)
            let values = try expectSuccess(result, settings: settings, key: syntheticKey)
            TestSupport.expectEqual(values["keychain_migration_done"], "true")
            TestSupport.expectEqual(values.count, 3)
        }
    }

    private static func createsPrivateDevelopmentSettings() throws {
        try withFixture(appName: "FreeFlow Dev") { directory, settings in
            let result = try runRecipe(home: directory, appName: "FreeFlow Dev")
            let values = try expectSuccess(result, settings: settings, key: syntheticKey)
            TestSupport.expectEqual(values["keychain_migration_done"], "true")
            let releaseSettings = directory.appendingPathComponent("Library/Application Support/FreeFlow/.settings")
            TestSupport.expect(
                !FileManager.default.fileExists(atPath: releaseSettings.path),
                "Development provisioning must leave the release directory untouched"
            )
        }
    }

    private static func preservesExistingCredentials() throws {
        for marker: String? in [nil, "false", ""] {
            try withFixture { directory, settings in
                var original = [
                    "groq_api_key": "synthetic-old-key",
                    "transcription_api_key": "synthetic-other-key",
                    "transcription_api_url": "https://transcription.example.invalid/v1",
                    "unknown_entry": "synthetic metadata 🧪"
                ]
                original["keychain_migration_done"] = marker
                try JSONEncoder().encode(original).write(to: settings)
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settings.path)
                let result = try runRecipe(home: directory)
                let values = try expectSuccess(result, settings: settings, key: syntheticKey)
                var expected = original
                expected["groq_api_key"] = syntheticKey
                expected["api_base_url"] = "https://api.groq.com/openai/v1"
                expected["keychain_migration_done"] = marker ?? "true"
                TestSupport.expectEqual(values, expected)
                let repeated = try runRecipe(home: directory)
                let reloaded = try expectSuccess(repeated, settings: settings, key: syntheticKey)
                TestSupport.expectEqual(reloaded, expected)
            }
        }
    }

    private static func acceptsCompleteBoundedInput() throws {
        for key in [syntheticKey, String(repeating: "a", count: 16_384)] {
            try withFixture { directory, settings in
                let result = try runRecipe(home: directory, input: Data(key.utf8))
                _ = try expectSuccess(result, settings: settings, key: key)
            }
        }
    }

    private static func refusesInvalidSettings() throws {
        let invalid = [
            Data("{invalid".utf8), Data("[]".utf8), Data("null".utf8),
            Data("{\"unknown\":42}".utf8), Data("{\"unknown\":null}".utf8),
            Data("{\"unknown\":{\"nested\":\"value\"}}".utf8),
            Data([0xff]), try JSONEncoder().encode(["unknown": String(repeating: "a", count: 1_048_576)])
        ]
        for original in invalid {
            try withFixture { directory, settings in
                try original.write(to: settings)
                let result = try runRecipe(home: directory, input: nil)
                try expectFailure(result, settings: settings, original: original)
            }
        }
    }

    private static func refusesCancelledOrInvalidInput() throws {
        let invalid = [
            Data(), Data("\n".utf8), Data(" \t\n".utf8), Data([0xff, 0x0a]),
            Data(repeating: 0x61, count: 16_385)
        ]
        for input in invalid {
            for exists in [false, true] {
                try withFixture { directory, settings in
                    let original = exists ? Data("{\"unknown\":\"synthetic\"}".utf8) : nil
                    try original?.write(to: settings)
                    let result = try runRecipe(home: directory, input: input)
                    try expectFailure(result, settings: settings, original: original)
                }
            }
        }
    }

    private static func refusesUnwritableDirectory() throws {
        try withFixture { directory, settings in
            let original = Data("{\"unknown\":\"synthetic\"}".utf8)
            try original.write(to: settings)
            let parent = settings.deletingLastPathComponent().path
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent) }
            let result = try runRecipe(home: directory)
            try expectFailure(result, settings: settings, original: original)
        }
    }

    private static func keepsSecretOffCommandsAndOutput() throws {
        try withFixture { directory, settings in
            let result = try runRecipe(home: directory, observeArguments: true)
            _ = try expectSuccess(result, settings: settings, key: syntheticKey)
            TestSupport.expect(!result.command.contains(syntheticKey), "The retained command must be constant")
            TestSupport.expect(!result.command.contains("gsk_..."), "The recipe must not embed a key placeholder")
            TestSupport.expect(!result.command.contains("plutil"), "Credential values must not reach plutil argv")
            TestSupport.expect(!result.command.contains("osascript"), "Credential values must not reach osascript argv")
            TestSupport.expect(
                result.environment.values.allSatisfy { !$0.contains(syntheticKey) },
                "The key must not enter the child environment"
            )
            TestSupport.expect(
                result.sampledArguments.contains(where: containsRubyProcess),
                "The protected-input Ruby process must be observed"
            )
            TestSupport.expect(
                result.sampledArguments.allSatisfy { !$0.contains(syntheticKey) },
                "The key must not enter sampled process arguments"
            )
        }
    }

    private static func expectSuccess(_ result: RecipeResult, settings: URL, key: String) throws -> [String: String] {
        TestSupport.expectEqual(result.status, 0)
        TestSupport.expectEqual(result.output, "")
        let values = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: settings))
        TestSupport.expect(values["groq_api_key"] == key, "The exact stdin key must reach settings as data")
        TestSupport.expectEqual(values["api_base_url"], "https://api.groq.com/openai/v1")
        let attributes = try FileManager.default.attributesOfItem(atPath: settings.path)
        TestSupport.expectEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        return values
    }

    private static func expectFailure(_ result: RecipeResult, settings: URL, original: Data?) throws {
        TestSupport.expect(result.status != 0, "Invalid or cancelled provisioning must fail")
        TestSupport.expectEqual(result.output, "Credential update cancelled or failed.\n")
        if let original {
            let saved = try Data(contentsOf: settings)
            TestSupport.expectEqual(saved, original)
        } else {
            TestSupport.expect(!FileManager.default.fileExists(atPath: settings.path), "No file may be promoted")
        }
    }

    private static func withFixture(appName: String = "FreeFlow", _ body: (URL, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let settings = directory.appendingPathComponent("Library/Application Support/\(appName)/.settings")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory, settings)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: settings.deletingLastPathComponent().path)
        TestSupport.expect(remaining.allSatisfy { $0 == ".settings" }, "No temporary credential file may remain")
    }

    private static func runRecipe(
        home: URL, appName: String = "FreeFlow",
        input: Data? = Data((syntheticKey + "\n").utf8), observeArguments: Bool = false
    ) throws -> RecipeResult {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let section = readme.components(separatedBy: "### API credentials")[1]
        let recipe = section.components(separatedBy: "```bash\n")[1]
            .components(separatedBy: "```")[0]
            .replacingOccurrences(of: "Application Support/FreeFlow/", with: "Application Support/\(appName)/")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", recipe]
        let environment = ["HOME": home.path, "CFFIXED_USER_HOME": home.path, "PATH": "/usr/bin:/bin"]
        process.environment = environment
        let output = Pipe()
        let standardInput = Pipe()
        process.standardInput = standardInput
        process.standardOutput = output
        process.standardError = output
        try process.run()
        var samples: [String] = []
        if observeArguments {
            let observationDeadline = Date().addingTimeInterval(3)
            while process.isRunning && Date() < observationDeadline {
                let arguments = try processArguments(root: process.processIdentifier)
                samples.append(arguments)
                if containsRubyProcess(arguments) { break }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        if process.isRunning, let input {
            try standardInput.fileHandleForWriting.write(contentsOf: input)
        }
        try standardInput.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            if observeArguments { samples.append(try processArguments(root: process.processIdentifier)) }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            process.terminate()
            throw CocoaError(.executableRuntimeMismatch)
        }
        process.waitUntilExit()
        let captured = output.fileHandleForReading.readDataToEndOfFile()
        return RecipeResult(
            status: process.terminationStatus, output: String(decoding: captured, as: UTF8.self),
            command: (["/bin/bash"] + (process.arguments ?? [])).joined(separator: " "),
            environment: environment, sampledArguments: samples
        )
    }

    private static func processArguments(root: Int32) throws -> String {
        let table = try ps(["-axo", "pid=,ppid="])
        let pairs = table.split(separator: "\n").compactMap { line -> (Int32, Int32)? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, let pid = Int32(fields[0]), let parent = Int32(fields[1]) else { return nil }
            return (pid, parent)
        }
        var identifiers: Set<Int32> = [root]
        for _ in 0..<8 {
            for (pid, parent) in pairs where identifiers.contains(parent) { identifiers.insert(pid) }
        }
        return try ps(["-ww", "-p", identifiers.sorted().map(String.init).joined(separator: ","), "-o", "ucomm=,command="])
    }

    private static func containsRubyProcess(_ snapshot: String) -> Bool {
        snapshot.split(separator: "\n").contains { $0.split(whereSeparator: \.isWhitespace).first == "ruby" }
    }

    private static func ps(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
