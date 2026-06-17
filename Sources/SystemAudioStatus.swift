import CoreAudio

enum SystemAudioStatus {
    struct VolumeScalarChange: Equatable {
        let element: UInt32
        let previousScalar: Float
    }

    struct OutputAudioDuckingSnapshot: Equatable {
        enum Restoration: Equatable {
            case unchanged
            case restoreVolumes([VolumeScalarChange])
            case unmute
        }

        let deviceID: AudioDeviceID?
        let restoration: Restoration

        init(deviceID: AudioDeviceID? = nil, restoration: Restoration) {
            self.deviceID = deviceID
            self.restoration = restoration
        }
    }

    private static let dictationDuckVolumeRatio: Float = 0.15
    private static let minimumDuckTargetScalar: Float = 0.02

    static func isDefaultOutputMuted() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        return isOutputMuted(deviceID: deviceID)
    }

    static func setDefaultOutputMuted(_ muted: Bool) -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        return setOutputMuted(muted, deviceID: deviceID)
    }

    static func defaultOutputVolume() -> Float? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }

        if let volume = readVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return volume
        }

        var maxChannelVolume: Float?
        for channel in 1...2 {
            if let volume = readVolume(deviceID: deviceID, element: AudioObjectPropertyElement(channel)) {
                maxChannelVolume = max(maxChannelVolume ?? 0, volume)
            }
        }
        return maxChannelVolume
    }

    static func beginDictationOutputDucking() -> OutputAudioDuckingSnapshot {
        guard let deviceID = defaultOutputDeviceID() else {
            return OutputAudioDuckingSnapshot(restoration: .unchanged)
        }

        if isOutputMuted(deviceID: deviceID) {
            return OutputAudioDuckingSnapshot(restoration: .unchanged)
        }

        let readableVolumes = readableOutputVolumeScalars(deviceID: deviceID)
        if !readableVolumes.isEmpty {
            var appliedChanges: [VolumeScalarChange] = []
            for (element, previousScalar) in readableVolumes {
                let duckedScalar = duckedVolumeScalar(for: previousScalar)
                guard duckedScalar < previousScalar - 0.001 else { continue }
                guard writeVolume(deviceID: deviceID, element: AudioObjectPropertyElement(element), scalar: duckedScalar) else {
                    continue
                }
                appliedChanges.append(VolumeScalarChange(element: element, previousScalar: previousScalar))
            }

            if !appliedChanges.isEmpty {
                return OutputAudioDuckingSnapshot(
                    deviceID: deviceID,
                    restoration: .restoreVolumes(appliedChanges)
                )
            }
        }

        if setOutputMuted(true, deviceID: deviceID) {
            return OutputAudioDuckingSnapshot(deviceID: deviceID, restoration: .unmute)
        }

        return OutputAudioDuckingSnapshot(restoration: .unchanged)
    }

    static func restoreDictationOutputDucking(_ snapshot: OutputAudioDuckingSnapshot) {
        guard let deviceID = snapshot.deviceID else { return }

        switch snapshot.restoration {
        case .unchanged:
            return
        case .restoreVolumes(let changes):
            for change in changes {
                _ = writeVolume(
                    deviceID: deviceID,
                    element: AudioObjectPropertyElement(change.element),
                    scalar: change.previousScalar
                )
            }
        case .unmute:
            _ = setOutputMuted(false, deviceID: deviceID)
        }
    }

    private static func isOutputMuted(deviceID: AudioDeviceID) -> Bool {
        var muteValue: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &muteValue
        )

        guard status == noErr else { return false }
        return muteValue == 1
    }

    private static func setOutputMuted(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
        var muteValue: UInt32 = muted ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &muteValue
        )

        return status == noErr
    }

    private static func duckedVolumeScalar(for currentScalar: Float) -> Float {
        let clampedCurrent = min(max(currentScalar, 0), 1)
        let scaled = clampedCurrent * dictationDuckVolumeRatio
        return min(max(scaled, minimumDuckTargetScalar), clampedCurrent)
    }

    private static func readableOutputVolumeScalars(deviceID: AudioDeviceID) -> [UInt32: Float] {
        var volumes: [UInt32: Float] = [:]

        if let masterVolume = readVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            volumes[UInt32(kAudioObjectPropertyElementMain)] = masterVolume
            return volumes
        }

        for channel in 1...2 {
            let element = AudioObjectPropertyElement(channel)
            if let volume = readVolume(deviceID: deviceID, element: element) {
                volumes[UInt32(channel)] = volume
            }
        }

        return volumes
    }

    private static func readVolume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Float? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        )

        return status == noErr ? value : nil
    }

    private static func writeVolume(
        deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement,
        scalar: Float
    ) -> Bool {
        var value = min(max(scalar, 0), 1)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &value
        )

        return status == noErr
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }
}
