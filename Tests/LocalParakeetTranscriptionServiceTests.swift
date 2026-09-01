import Foundation

private actor ProcessLaunchGate {
    private var reached = false
    private var reachedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        reached = true
        reachedContinuation?.resume()
        reachedContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilReached() async {
        guard !reached else { return }
        await withCheckedContinuation { reachedContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

enum LocalParakeetTranscriptionServiceTests {
    static func run() async {
        usesPredictableCPUCompute()
        await cancellationBeforeLaunchDoesNotRunHelper()
        parsesAndTrimsDedicatedTranscriptField()
        collapsesDecoderPunctuationRepetition()
        removesUnexpectedScriptArtifacts()
        rejectsResponsesWithoutTranscriptText()
    }

    private static func cancellationBeforeLaunchDoesNotRunHelper() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freeflow-local-cancel-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("fake-helper")
        let marker = URL(fileURLWithPath: helper.path + ".ran")
        let modelDirectory = root.appendingPathComponent("models", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            try Data("#!/bin/sh\n/usr/bin/touch \"$0.ran\"\n".utf8).write(to: helper)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
            let launchGate = ProcessLaunchGate()
            let service = try LocalParakeetTranscriptionService(
                modelDirectory: modelDirectory,
                executableURL: helper,
                beforeProcessLaunch: {
                    await launchGate.pause()
                }
            )
            let task = Task.detached { try await service.prewarm() }
            await launchGate.waitUntilReached()
            task.cancel()
            await launchGate.release()
            do {
                try await task.value
                TestSupport.expect(false, "Cancelled prewarm unexpectedly succeeded")
            } catch is CancellationError {
                TestSupport.expect(true, "Prewarm cancellation propagated")
            }
            TestSupport.expect(
                !FileManager.default.fileExists(atPath: marker.path),
                "A helper launched after prewarm was already cancelled"
            )
        } catch {
            TestSupport.expect(false, "Cancellation regression test failed: \(error)")
        }
    }

    private static func usesPredictableCPUCompute() {
        TestSupport.expect(
            LocalParakeetTranscriptionService.computeUnits == "cpu",
            "Local transcription should avoid sporadic Neural Engine cold-start stalls"
        )
    }

    private static func collapsesDecoderPunctuationRepetition() {
        let data = Data("Versie 7.. Really??? Yes!!".utf8)
        let transcript = try? LocalParakeetTranscriptionService.parseTranscript(from: data)
        TestSupport.expectEqual(transcript, "Versie 7.. Really??? Yes!")
    }

    private static func removesUnexpectedScriptArtifacts() {
        let data = Data("naïeve façade — goed. Ю".utf8)
        let transcript = try? LocalParakeetTranscriptionService.parseTranscript(from: data)
        TestSupport.expectEqual(transcript, "naïeve façade — goed.")

        let nonLatin = Data("Dit is naam Юрий".utf8)
        let preservedName = try? LocalParakeetTranscriptionService.parseTranscript(from: nonLatin)
        TestSupport.expectEqual(preservedName, "Dit is naam Юрий")

        let fullNonLatin = Data("Добрый день. Ю".utf8)
        let preservedTranscript = try? LocalParakeetTranscriptionService.parseTranscript(from: fullNonLatin)
        TestSupport.expectEqual(preservedTranscript, "Добрый день. Ю")
    }

    private static func parsesAndTrimsDedicatedTranscriptField() {
        let data = Data("  Hallo wereld. \n".utf8)
        let transcript = try? LocalParakeetTranscriptionService.parseTranscript(from: data)
        TestSupport.expectEqual(transcript, "Hallo wereld.")
    }

    private static func rejectsResponsesWithoutTranscriptText() {
        let data = Data()
        do {
            _ = try LocalParakeetTranscriptionService.parseTranscript(from: data)
            TestSupport.expect(false, "Empty helper output should fail parsing")
        } catch {
            TestSupport.expect(true, "Empty helper output correctly rejected")
        }
    }
}
