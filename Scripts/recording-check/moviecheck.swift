// moviecheck: reads one movie the recording rig wrote (docs/recording-plan.md, Tests, "The rig") with AVFoundation,
// reading only: it never decodes the picture (its samples are read as they are, passthrough). It prints one JSON
// object: the movie's duration; the picture's track (codec, its edit's start, every sample's time and whether it
// is a sync sample); the sound's (codec, duration, and with --mac-start the test tone's clicks, each with how far it
// lies from the whole second of the Mac's clock it belongs to: the sound decoded to PCM for that).
//
//   moviecheck MOVIE [--mac-start SECONDS]
//
// --mac-start: the movie's 0:00 on the Mac's clock (recordcheck's summary.json, `partStarts`). A synthetic host's
// test tone clicks at each whole second of the Mac's clock (TestTone): the click at Mac second k belongs at movie
// time k − mac-start.
import AVFoundation
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
var args = Array(CommandLine.arguments.dropFirst())
var macStart: Double?
if let i = args.firstIndex(of: "--mac-start"), i + 1 < args.count {
    macStart = Double(args[i + 1]); args.removeSubrange(i...(i + 1))
}
guard args.count == 1 else { print("usage: moviecheck MOVIE [--mac-start SECONDS]"); exit(2) }
let url = URL(fileURLWithPath: args[0])

func fourCC(_ f: CMFormatDescription?) -> String {
    guard let f else { return "none" }
    let c = CMFormatDescriptionGetMediaSubType(f)
    let bytes = [UInt8((c >> 24) & 0xFF), UInt8((c >> 16) & 0xFF), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF)]
    return String(decoding: bytes, as: UTF8.self)
}

func run() async -> [String: Any] {
    var report: [String: Any] = ["movie": url.lastPathComponent]
    let asset = AVURLAsset(url: url)
    guard let duration = try? await asset.load(.duration) else { report["error"] = "the movie does not open"; return report }
    report["duration"] = duration.seconds
    let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
    let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
    if let track = videoTracks.first {
        var video: [String: Any] = [:]
        let formats = (try? await track.load(.formatDescriptions)) ?? []
        video["codec"] = fourCC(formats.first)
        if let range = try? await track.load(.timeRange) { video["start"] = range.start.seconds; video["duration"] = range.duration.seconds }
        if let segments = try? await track.load(.segments) {
            video["edits"] = segments.map { ["mediaStart": $0.timeMapping.source.start.seconds, "movieStart": $0.timeMapping.target.start.seconds,
                                             "duration": $0.timeMapping.target.duration.seconds, "empty": $0.isEmpty] }
        }
        if let reader = try? AVAssetReader(asset: asset) {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            reader.add(output)
            reader.startReading()
            var samples: [[Any]] = []
            while let s = output.copyNextSampleBuffer() {
                guard CMSampleBufferGetNumSamples(s) > 0 else { continue }
                var sync = true
                if let a = CMSampleBufferGetSampleAttachmentsArray(s, createIfNecessary: false) as? [[CFString: Any]],
                   let first = a.first, let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool { sync = !notSync }
                samples.append([CMSampleBufferGetPresentationTimeStamp(s).seconds, sync, CMSampleBufferGetTotalSampleSize(s)])
            }
            video["samples"] = samples
            video["readerStatus"] = reader.status.rawValue
        }
        report["video"] = video
    }
    if let track = audioTracks.first {
        var audio: [String: Any] = [:]
        let formats = (try? await track.load(.formatDescriptions)) ?? []
        audio["codec"] = fourCC(formats.first)
        if let range = try? await track.load(.timeRange) { audio["start"] = range.start.seconds; audio["duration"] = range.duration.seconds }
        if let reader = try? AVAssetReader(asset: asset) {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                                           AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
                                           AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            reader.add(output)
            reader.startReading()
            // The clicks: a frame over 0.2 (the click peaks at −6 dBFS, 0.5; the tone at −30 dBFS, 0.03, never
            // reaches it) after at least 0.1 s with none; its onset is about 1 ms into the click (its window's rise).
            var clicks: [Double] = []
            var quiet = 4800, frames = 0, loud = 0.0
            var first: Double?
            while let s = output.copyNextSampleBuffer() {
                let pts = CMSampleBufferGetPresentationTimeStamp(s).seconds
                if first == nil { first = pts }
                guard let block = CMSampleBufferGetDataBuffer(s) else { continue }
                var length = 0
                var pointer: UnsafeMutablePointer<CChar>?
                guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                                  dataPointerOut: &pointer) == noErr, let pointer else { continue }
                let n = length / (2 * MemoryLayout<Float>.size)
                pointer.withMemoryRebound(to: Float.self, capacity: 2 * n) { x in
                    for i in 0..<n {
                        let v = max(abs(x[2 * i]), abs(x[2 * i + 1]))
                        loud = max(loud, Double(v))
                        if v > 0.2 {
                            if quiet >= 4800 { clicks.append(pts + Double(i) / 48_000 - 0.001) }
                            quiet = 0
                        } else {
                            quiet += 1
                        }
                    }
                }
                frames += n
            }
            audio["frames"] = frames
            audio["firstPTS"] = first ?? -1
            audio["loudest"] = loud
            audio["clicks"] = clicks
            if let macStart {
                // Each click against the whole second of the Mac's clock it belongs to.
                audio["clickOffsetsMs"] = clicks.map { t -> Double in
                    let mac = t + macStart
                    return (mac - mac.rounded()) * 1000
                }
            }
            audio["readerStatus"] = reader.status.rawValue
        }
        report["audio"] = audio
    }
    return report
}

let done = DispatchSemaphore(value: 0)
var result: [String: Any] = [:]
Task {
    result = await run()
    done.signal()
}
done.wait()
let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
