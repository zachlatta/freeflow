import Foundation

enum JSONPreferencesTests {
    static func run() {
        do {
            try loadsShortcutData()
            try loadsShortcutString()
            try loadsMacroDataAndString()
            try generatesMissingMacroIDs()
            try rejectsMalformedPreferences()
            try preservesMacroRoundTrips()
            try preservesShortcutRoundTrips()
        } catch {
            fatalError("JSON preference fixture failed: \(error)")
        }
    }

    private static func loadsShortcutData() throws {
        try withDefaults { defaults in
            let input = Data(
                #"{"modifiers":0,"kind":"modifierKey","keyCode":63,"keyDisplay":"Fn","preset":"fn"}"#.utf8
            )
            defaults.set(input, forKey: "hold_shortcut")
            let data = try requiredData(forKey: "hold_shortcut", in: defaults)
            let binding = try JSONDecoder().decode(ShortcutBinding.self, from: data)
            TestSupport.expectEqual(binding.keyCode, 63)
            TestSupport.expectEqual(binding.keyDisplay, "Fn")
            TestSupport.expectEqual(binding.kind, .modifierKey)
            TestSupport.expectEqual(binding.modifiers.rawValue, 0)
            TestSupport.expectEqual(binding.preset, .fnKey)
        }
    }

    private static func loadsShortcutString() throws {
        try withDefaults { defaults in
            defaults.set(
                #"{"modifiers":0,"kind":"modifierKey","keyCode":54,"keyDisplay":"Right Command"}"#,
                forKey: "saved_toggle_custom_shortcut"
            )
            let data = try requiredData(forKey: "saved_toggle_custom_shortcut", in: defaults)
            let binding = try JSONDecoder().decode(ShortcutBinding.self, from: data)
            TestSupport.expectEqual(binding.keyCode, 54)
            TestSupport.expectEqual(binding.keyDisplay, "Right Command")
            TestSupport.expectEqual(binding.kind, .modifierKey)
            TestSupport.expectEqual(binding.modifiers.rawValue, 0)
            TestSupport.expectEqual(binding.preset, nil)
        }
    }

    private static func loadsMacroDataAndString() throws {
        try withDefaults { defaults in
            let json = #"[{"id":"A5DFB5E3-94F1-4B54-A574-409048746191","command":"address","payload":"synthetic address"}]"#
            for input: Any in [Data(json.utf8), json] {
                defaults.set(input, forKey: "voice_macros")
                let data = try requiredData(forKey: "voice_macros", in: defaults)
                let macros = try JSONDecoder().decode([VoiceMacro].self, from: data)
                TestSupport.expectEqual(macros.count, 1)
                TestSupport.expectEqual(macros[0].id.uuidString, "A5DFB5E3-94F1-4B54-A574-409048746191")
                TestSupport.expectEqual(macros[0].command, "address")
                TestSupport.expectEqual(macros[0].payload, "synthetic address")
            }
        }
    }

    private static func generatesMissingMacroIDs() throws {
        try withDefaults { defaults in
            let json = #"[{"command":"first","payload":"one"},{"command":"second","payload":"two"}]"#
            for input: Any in [Data(json.utf8), json] {
                defaults.set(input, forKey: "voice_macros")
                let data = try requiredData(forKey: "voice_macros", in: defaults)
                let macros = try JSONDecoder().decode([VoiceMacro].self, from: data)
                TestSupport.expectEqual(macros.count, 2)
                TestSupport.expect(macros[0].id != macros[1].id, "Each omitted ID must receive its own UUID")
                TestSupport.expectEqual(macros[0].command, "first")
                TestSupport.expectEqual(macros[1].payload, "two")
                defaults.set(try JSONEncoder().encode(macros), forKey: "voice_macros")
                let saved = try requiredData(forKey: "voice_macros", in: defaults)
                let reloaded = try JSONDecoder().decode([VoiceMacro].self, from: saved)
                TestSupport.expectEqual(reloaded, macros)
            }
        }
    }

    private static func rejectsMalformedPreferences() throws {
        try withDefaults { defaults in
            TestSupport.expectEqual(JSONPreferences.data(forKey: "missing", in: defaults), nil)
            for input: Any in [true, 42, ["synthetic"], ["synthetic": "value"]] {
                defaults.set(input, forKey: "unsupported")
                TestSupport.expectEqual(JSONPreferences.data(forKey: "unsupported", in: defaults), nil)
            }
            defaults.set("{invalid", forKey: "hold_shortcut")
            let shortcutData = try requiredData(forKey: "hold_shortcut", in: defaults)
            TestSupport.expectEqual(try? JSONDecoder().decode(ShortcutBinding.self, from: shortcutData), nil)
            defaults.set(Data("{invalid".utf8), forKey: "voice_macros")
            let macroData = try requiredData(forKey: "voice_macros", in: defaults)
            TestSupport.expectEqual(try? JSONDecoder().decode([VoiceMacro].self, from: macroData), nil)
            let invalidID = Data(#"[{"id":"invalid","command":"first","payload":"one"}]"#.utf8)
            TestSupport.expectEqual(try? JSONDecoder().decode([VoiceMacro].self, from: invalidID), nil)
            let missingPayload = Data(#"[{"command":"first"}]"#.utf8)
            TestSupport.expectEqual(try? JSONDecoder().decode([VoiceMacro].self, from: missingPayload), nil)
            let missingCommand = Data(#"[{"payload":"one"}]"#.utf8)
            TestSupport.expectEqual(try? JSONDecoder().decode([VoiceMacro].self, from: missingCommand), nil)
            let invalidPayload = Data(#"[{"command":"first","payload":42}]"#.utf8)
            TestSupport.expectEqual(try? JSONDecoder().decode([VoiceMacro].self, from: invalidPayload), nil)
        }
    }

    private static func preservesMacroRoundTrips() throws {
        try withDefaults { defaults in
            let initial = [VoiceMacro(
                id: UUID(uuidString: "A5DFB5E3-94F1-4B54-A574-409048746191")!,
                command: "line break",
                payload: "first\nsecond 🗣️"
            )]
            let encoded = try JSONEncoder().encode(initial)
            let object = try JSONSerialization.jsonObject(with: encoded) as? [[String: String]]
            TestSupport.expectEqual(object?.first?["id"], "A5DFB5E3-94F1-4B54-A574-409048746191")
            defaults.set(encoded, forKey: "voice_macros")
            let data = try requiredData(forKey: "voice_macros", in: defaults)
            let decoded = try JSONDecoder().decode([VoiceMacro].self, from: data)
            TestSupport.expectEqual(decoded, initial)
            TestSupport.expect(defaults.object(forKey: "voice_macros") is Data, "App writes must remain Data")
        }
    }

    private static func preservesShortcutRoundTrips() throws {
        try withDefaults { defaults in
            let initial = ShortcutBinding(
                keyCode: 46,
                keyDisplay: "M",
                modifiers: [.command, .shift],
                kind: .key,
                preset: nil
            )
            defaults.set(try JSONEncoder().encode(initial), forKey: "copy_again_shortcut")
            let data = try requiredData(forKey: "copy_again_shortcut", in: defaults)
            let decoded = try JSONDecoder().decode(ShortcutBinding.self, from: data)
            TestSupport.expectEqual(decoded, initial)
        }
    }

    private static func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "FreeFlowTests.JSONPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private static func requiredData(forKey key: String, in defaults: UserDefaults) throws -> Data {
        guard let data = JSONPreferences.data(forKey: key, in: defaults) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return data
    }
}
