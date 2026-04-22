import CoreAudio

enum SystemAudioStatus {
    static func isDefaultOutputMuted() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }

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
