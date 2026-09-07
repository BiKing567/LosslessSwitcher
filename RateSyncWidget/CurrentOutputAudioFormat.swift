import CoreAudio
import Foundation

enum CurrentOutputAudioFormat {
    static func load(date: Date = Date()) -> SharedAudioFormat? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }

        for streamID in outputStreamIDs(for: deviceID) {
            let format = readFormat(
                from: streamID,
                selector: kAudioStreamPropertyPhysicalFormat
            ) ?? readFormat(
                from: streamID,
                selector: kAudioStreamPropertyVirtualFormat
            )

            guard let format,
                  format.mSampleRate.isFinite,
                  format.mSampleRate > 0 else {
                continue
            }

            let bitDepth = format.mBitsPerChannel > 0
                ? Int(format.mBitsPerChannel)
                : nil
            return SharedAudioFormat(
                sampleRate: format.mSampleRate,
                bitDepth: bitDepth,
                updatedAt: date
            )
        }

        return nil
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        ) == noErr,
        deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }

        return deviceID
    }

    private static func outputStreamIDs(for deviceID: AudioDeviceID) -> [AudioStreamID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let streamCount = Int(dataSize) / MemoryLayout<AudioStreamID>.stride
        guard streamCount > 0 else { return [] }

        var streamIDs = Array(repeating: AudioStreamID(0), count: streamCount)
        var status: OSStatus = -1
        streamIDs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            status = AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }

        return status == noErr ? streamIDs : []
    }

    private static func readFormat(
        from streamID: AudioStreamID,
        selector: AudioObjectPropertySelector
    ) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        guard AudioObjectGetPropertyData(
            streamID,
            &address,
            0,
            nil,
            &dataSize,
            &format
        ) == noErr else {
            return nil
        }

        return format
    }
}
