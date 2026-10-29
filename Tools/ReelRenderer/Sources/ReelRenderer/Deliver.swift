// Deliver.swift — muxing the score (AVAssetWriter: video passthrough + AAC audio input), the contact
// sheet (AVAssetImageGenerator) and the sign-off checks (§11).
import AppKit
import AVFoundation
import CoreImage
import Foundation

func loadSync<T>(_ body: @escaping () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    var result: Result<T, Error>!
    Task.detached {
        do { result = .success(try await body()) } catch { result = .failure(error) }
        sem.signal()
    }
    sem.wait()
    return try result.get()
}

// MARK: - Mux (§10.1): the silent MP4's H.264 samples passed through, the score encoded to AAC-LC 256 kbps

func muxScore(args: [String]) throws {
    let video = URL(fileURLWithPath: args[0]), wav = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
    let asset = AVURLAsset(url: video)
    let (vtrack, duration) = try loadSync { () -> (AVAssetTrack, CMTime) in
        (try await asset.loadTracks(withMediaType: .video).first!, try await asset.load(.duration))
    }
    let formats = try loadSync { try await vtrack.load(.formatDescriptions) }
    try? FileManager.default.removeItem(at: out)
    let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
    let vin = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formats.first)
    vin.expectsMediaDataInRealTime = false
    let ain = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 256_000,
    ])
    ain.expectsMediaDataInRealTime = false
    writer.add(vin); writer.add(ain)

    let vreader = try AVAssetReader(asset: asset)
    let vout = AVAssetReaderTrackOutput(track: vtrack, outputSettings: nil)
    vreader.add(vout)
    let audioFile = try AVAudioFile(forReading: wav, commonFormat: .pcmFormatFloat32, interleaved: false)
    let fmt = audioFile.processingFormat
    guard vreader.startReading(), writer.startWriting() else { throw writer.error ?? vreader.error ?? NSError(domain: "mux", code: 1) }
    writer.startSession(atSourceTime: .zero)
    let totalAudioFrames = AVAudioFramePosition((duration.seconds * 48_000).rounded())

    let group = DispatchGroup()
    let vq = DispatchQueue(label: "mux.video"), aq = DispatchQueue(label: "mux.audio")
    group.enter()
    vin.requestMediaDataWhenReady(on: vq) {
        while vin.isReadyForMoreMediaData {
            if let s = vout.copyNextSampleBuffer() { vin.append(s) } else { vin.markAsFinished(); group.leave(); return }
        }
    }
    group.enter()
    var written: AVAudioFramePosition = 0
    ain.requestMediaDataWhenReady(on: aq) {
        while ain.isReadyForMoreMediaData {
            let remaining = totalAudioFrames - written
            if remaining <= 0 { ain.markAsFinished(); group.leave(); return }
            let n = AVAudioFrameCount(min(4096, remaining))
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
            do { try audioFile.read(into: buf, frameCount: n) } catch { ain.markAsFinished(); group.leave(); return }
            if buf.frameLength == 0 { ain.markAsFinished(); group.leave(); return }
            var asbd = fmt.streamDescription.pointee
            var desc: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                           magicCookie: nil, extensions: nil, formatDescriptionOut: &desc)
            var sb: CMSampleBuffer?
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                            presentationTimeStamp: CMTime(value: written, timescale: 48_000), decodeTimeStamp: .invalid)
            CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
                                 formatDescription: desc, sampleCount: CMItemCount(buf.frameLength), sampleTimingEntryCount: 1,
                                 sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sb)
            CMSampleBufferSetDataBufferFromAudioBufferList(sb!, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                                                          flags: 0, bufferList: buf.audioBufferList)
            _ = asbd
            ain.append(sb!)
            written += AVAudioFramePosition(buf.frameLength)
        }
    }
    group.wait()
    let sem = DispatchSemaphore(value: 0)
    writer.finishWriting { sem.signal() }
    sem.wait()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "mux", code: 2) }
    let bytes = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
    print("mux: \(out.path) (\(bytes) bytes)")
}

// MARK: - Contact sheet (§11.1)

/// v3: one tile per shot (35), at a moment that shows the shot's point. S01–S24 as v2; S25–S27 the remote
/// beats; S28–S35 are v2's S25–S32 8.0 s later.
let sheetTimes: [(String, Double)] = [
    ("S01", 1.6), ("S02", 4.0), ("S03", 5.6), ("S04", 7.0), ("S05", 8.8), ("S06", 11.7),
    ("S07", 12.9), ("S08", 15.8), ("S09", 16.9), ("S10", 18.9), ("S11", 20.6), ("S12", 22.4),
    ("S13", 24.8), ("S14", 27.9), ("S15", 29.9), ("S16", 33.9), ("S17", 36.3), ("S18", 39.4),
    ("S19", 41.4), ("S20", 44.0), ("S21", 48.0), ("S22", 49.8), ("S23", 52.4), ("S24", 56.6),
    ("S25", 59.6), ("S26", 62.0), ("S27", 64.8), ("S28", 66.4), ("S29", 68.0), ("S30", 70.0),
    ("S31", 72.8), ("S32", 75.2), ("S33", 77.6), ("S34", 81.0), ("S35", 82.5),
]

func contactSheet(args: [String]) throws {
    let movie = URL(fileURLWithPath: args[0]), out = URL(fileURLWithPath: args[1])
    let asset = AVURLAsset(url: movie)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    gen.appliesPreferredTrackTransform = true
    let cols = 6, tileW = 300, tileH = 169, gutter = 14, label = 26
    let rows = (sheetTimes.count + cols - 1) / cols
    let W = cols * tileW + (cols + 1) * gutter
    let titleH = 56
    let H = titleH + rows * (tileH + label) + (rows + 1) * gutter
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.07, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.interpolationQuality = .high
    func text(_ s: String, _ x: Int, _ y: Int, _ size: CGFloat, _ weight: NSFont.Weight, _ gray: CGFloat) {
        let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                          .foregroundColor: NSColor(white: gray, alpha: 1)])
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(a), ctx)
    }
    text("Sill sizzle reel v3.1 · contact sheet · one frame per shot (from the MP4) · S24–S27: Wi‑Fi, Wired, Direct, Remote", gutter, H - 36, 18, .semibold, 0.85)
    for (k, (id, t)) in sheetTimes.enumerated() {
        let (cg, _) = try loadSync { try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)) }
        let col = k % cols, row = k / cols
        let x = gutter + col * (tileW + gutter)
        let yTop = titleH + gutter + row * (tileH + label + gutter)
        let y = H - yTop - label - tileH
        ctx.draw(cg, in: CGRect(x: x, y: y, width: tileW, height: tileH))
        text(String(format: "%@ · %.1f s", id, t), x, y + tileH + 8, 14, .medium, 0.72)
    }
    writePNG(ctx.makeImage()!, to: out)
    print("sheet: \(sheetTimes.count) tiles → \(W)x\(H) \(out.path)")
}

// MARK: - Verify (§11.2)

/// Walks MP4 boxes and reports whether any track carries an edit list.
func mp4Boxes(_ url: URL) throws -> [String] {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    var found: [String] = []
    func walk(_ start: Int, _ end: Int, _ depth: Int) {
        var p = start
        while p + 8 <= end {
            var size = Int(data[p]) << 24 | Int(data[p + 1]) << 16 | Int(data[p + 2]) << 8 | Int(data[p + 3])
            let type = String(bytes: data[(p + 4)..<(p + 8)], encoding: .ascii) ?? "????"
            var header = 8
            if size == 1, p + 16 <= end {
                size = 0
                for i in 0..<8 { size = size << 8 | Int(data[p + 8 + i]) }
                header = 16
            } else if size == 0 { size = end - p }
            guard size >= header, p + size <= end else { break }
            found.append(String(repeating: " ", count: depth) + type)
            if ["moov", "trak", "mdia", "minf", "stbl", "edts", "udta"].contains(type) {
                walk(p + header, p + size, depth + 1)
            }
            p += size
        }
    }
    walk(0, data.count, 0)
    return found
}

func verify(args: [String]) throws {
    for path in args {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let (duration, vtracks, atracks) = try loadSync { () -> (CMTime, [AVAssetTrack], [AVAssetTrack]) in
            (try await asset.load(.duration), try await asset.loadTracks(withMediaType: .video),
             try await asset.loadTracks(withMediaType: .audio))
        }
        print("\n\(url.lastPathComponent): duration \(String(format: "%.4f", duration.seconds)) s, video tracks \(vtracks.count), audio tracks \(atracks.count)")
        guard let v = vtracks.first else { continue }
        let (size, fps, rate, formats, vrange) = try loadSync { () -> (CGSize, Float, Float, [CMFormatDescription], CMTimeRange) in
            (try await v.load(.naturalSize), try await v.load(.nominalFrameRate), try await v.load(.estimatedDataRate),
             try await v.load(.formatDescriptions), try await v.load(.timeRange))
        }
        let fd = formats.first!
        let codec = CMFormatDescriptionGetMediaSubType(fd)
        let codecStr = String(bytes: [24, 16, 8, 0].map { UInt8((codec >> $0) & 0xFF) }, encoding: .ascii) ?? "?"
        var profile = "?"
        if let ext = CMFormatDescriptionGetExtensions(fd) as? [String: Any],
           let atoms = ext["SampleDescriptionExtensionAtoms"] as? [String: Any], let avcC = atoms["avcC"] as? Data, avcC.count > 3 {
            let p = avcC[1]
            profile = p == 100 ? "High (100)" : p == 77 ? "Main (77)" : p == 66 ? "Baseline (66)" : "\(p)"
            profile += String(format: " level %.1f", Double(avcC[3]) / 10)
        }
        let prim = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String ?? "?"
        let tf = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String ?? "?"
        let mx = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String ?? "?"
        print("  video: \(codecStr) \(profile), \(Int(size.width))x\(Int(size.height)), nominal \(fps) fps, \(String(format: "%.1f", rate / 1e6)) Mbps, range \(String(format: "%.4f", vrange.start.seconds))+\(String(format: "%.4f", vrange.duration.seconds))")
        print("  colour: \(prim) / \(tf) / \(mx)")
        // Frame count and timing: every sample's PTS.
        let reader = try AVAssetReader(asset: asset)
        let o = AVAssetReaderTrackOutput(track: v, outputSettings: nil)
        reader.add(o); reader.startReading()
        var pts: [Double] = []
        var sync = 0
        while let s = o.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(s) == 0 { continue }
            pts.append(CMSampleBufferGetPresentationTimeStamp(s).seconds)
            if let att = CMSampleBufferGetSampleAttachmentsArray(s, createIfNecessary: false) as? [[CFString: Any]],
               att.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true { sync += 1 }
        }
        let gaps = zip(pts.dropFirst(), pts).map { $0 - $1 }
        print("  frames \(pts.count), first \(String(format: "%.4f", pts.first ?? -1)), last \(String(format: "%.4f", pts.last ?? -1)), step \(String(format: "%.5f…%.5f", gaps.min() ?? 0, gaps.max() ?? 0)), sync frames \(sync)")
        let boxes = try mp4Boxes(url)
        let edts = boxes.filter { $0.trimmingCharacters(in: .whitespaces) == "elst" }.count
        print("  edit lists (elst): \(edts)")
        if let a = atracks.first {
            let (afd, arange) = try loadSync { (try await a.load(.formatDescriptions), try await a.load(.timeRange)) }
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(afd.first!)?.pointee {
                let id = asbd.mFormatID
                let idStr = String(bytes: [24, 16, 8, 0].map { UInt8((id >> $0) & 0xFF) }, encoding: .ascii) ?? "?"
                print("  audio: \(idStr) \(Int(asbd.mSampleRate)) Hz, \(asbd.mChannelsPerFrame) ch, range \(String(format: "%.4f+%.4f", arange.start.seconds, arange.duration.seconds))")
            }
            // Levels: overall peak, RMS, and the 57.60–58.00 window (v2).
            let ar = try AVAssetReader(asset: asset)
            let ao = AVAssetReaderTrackOutput(track: a, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
                                                                         AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
                                                                         AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2])
            ar.add(ao); ar.startReading()
            var peak: Float = 0, sumSq = 0.0, n = 0.0, silPeak: Float = 0, idx = 0, innerPeak: Float = 0
            // v3: the silence moved with Act IV (65.60–66.00).
            let silA = Int(65.60 * 48_000), silB = Int(66.00 * 48_000)
            let inA = Int(65.65 * 48_000), inB = Int(65.95 * 48_000)
            var nonzero = 0
            while let s = ao.copyNextSampleBuffer() {
                guard let bb = CMSampleBufferGetDataBuffer(s) else { continue }
                var len = 0; var ptr: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
                let count = len / 4
                ptr!.withMemoryRebound(to: Float.self, capacity: count) { f in
                    for i in 0..<count {
                        let x = f[i]; let frame = (idx + i) / 2
                        peak = max(peak, abs(x)); sumSq += Double(x * x); n += 1
                        if frame >= silA && frame < silB { silPeak = max(silPeak, abs(x)); if x != 0 { nonzero += 1 } }
                        if frame >= inA && frame < inB { innerPeak = max(innerPeak, abs(x)) }
                    }
                }
                idx += count
            }
            let db = { (x: Double) in x > 0 ? 20 * log10(x) : -999 }
            print(String(format: "  audio levels: peak %.2f dBFS, RMS %.2f dBFS, 65.60–66.00 peak %@ (%d non-zero samples), 65.65–65.95 peak %@",
                         db(Double(peak)), db((sumSq / max(n, 1)).squareRoot()),
                         silPeak == 0 ? "digital silence (0)" : String(format: "%.1f dBFS", db(Double(silPeak))), nonzero,
                         innerPeak == 0 ? "digital silence (0)" : String(format: "%.1f dBFS", db(Double(innerPeak)))))
        }
        // Blacks: frame 3951 (65.85 s, inside the 0.4 s of true black; v2's 3471) must decode to Y 16.
        let yr = try AVAssetReader(asset: asset)
        yr.timeRange = CMTimeRange(start: CMTime(value: 3951, timescale: 60), duration: CMTime(value: 1, timescale: 60))
        let yo = AVAssetReaderTrackOutput(track: v, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        yr.add(yo); yr.startReading()
        if let s = yo.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(s) {
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self)
            let bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            var hist = [Int](repeating: 0, count: 256)
            for y in 0..<CVPixelBufferGetHeightOfPlane(pb, 0) {
                for x in 0..<CVPixelBufferGetWidthOfPlane(pb, 0) { hist[Int(base[y * bpr + x])] += 1 }
            }
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            let used = hist.enumerated().filter { $0.element > 0 }.map { "Y\($0.offset)×\($0.element)" }
            print("  true black at 65.85 s (frame 3951): \(used.joined(separator: ", ")) (want all 16)")
        }
        // The hero (§11.2 check 3): mean luma of S10's stream area, frames 1118…1124 (v2: 1122 is the black one).
        let hr = try AVAssetReader(asset: asset)
        hr.timeRange = CMTimeRange(start: CMTime(value: 1118, timescale: 60), duration: CMTime(value: 7, timescale: 60))
        let ho = AVAssetReaderTrackOutput(track: v, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        hr.add(ho); hr.startReading()
        var hero: [String] = []
        while let s = ho.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(s) {
            let f = Int((CMSampleBufferGetPresentationTimeStamp(s).seconds * 60).rounded())
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self)
            let bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            var sum = 0, n = 0
            for y in stride(from: 520, to: 820, by: 2) { for x in stride(from: 420, to: 1500, by: 2) { sum += Int(base[y * bpr + x]); n += 1 } }
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            hero.append("\(f):\(sum / max(n, 1))")
        }
        print("  hero stream-area luma by frame (1122 should be the one black frame): \(hero.joined(separator: " "))")
    }
}

// MARK: - The video track's identity edit list
//
// AVAssetWriter writes an `edts/elst` for the video track even with frame reordering off (one entry: media
// time 0, the whole duration). It changes nothing, but §11.2 asks for no edit list, so the box is removed.
// Only a trailing `moov` is edited (no chunk offset moves); the audio track's edit list (AAC priming) stays.

private func u32(_ d: Data, _ i: Int) -> Int { Int(d[i]) << 24 | Int(d[i + 1]) << 16 | Int(d[i + 2]) << 8 | Int(d[i + 3]) }
private func put32(_ d: inout Data, _ i: Int, _ v: Int) {
    d[i] = UInt8((v >> 24) & 0xFF); d[i + 1] = UInt8((v >> 16) & 0xFF); d[i + 2] = UInt8((v >> 8) & 0xFF); d[i + 3] = UInt8(v & 0xFF)
}
private func boxes(_ d: Data, _ start: Int, _ end: Int) -> [(type: String, at: Int, size: Int)] {
    var out: [(String, Int, Int)] = []
    var p = start
    while p + 8 <= end {
        let size = u32(d, p)
        guard size >= 8, p + size <= end else { break }        // 64-bit sizes are not expected inside moov
        out.append((String(bytes: d[(p + 4)..<(p + 8)], encoding: .ascii) ?? "????", p, size))
        p += size
    }
    return out
}

func stripVideoEditList(_ url: URL) throws {
    var d = try Data(contentsOf: url)
    // Top level: 32-bit sizes for ftyp and moov; mdat may use a 64-bit size.
    var p = 0, moov: (Int, Int)?, lastEnd = 0
    while p + 8 <= d.count {
        var size = u32(d, p)
        let type = String(bytes: d[(p + 4)..<(p + 8)], encoding: .ascii) ?? "????"
        if size == 1 { size = 0; for k in 0..<8 { size = size << 8 | Int(d[p + 8 + k]) } }
        if size == 0 { size = d.count - p }
        if type == "moov" { moov = (p, size) }
        lastEnd = p + size
        p += size
    }
    guard let (mAt, mSize) = moov, mAt + mSize == lastEnd, lastEnd == d.count else {
        throw NSError(domain: "edts", code: 1, userInfo: [NSLocalizedDescriptionKey: "moov is not the last box; not editing"])
    }
    for trak in boxes(d, mAt + 8, mAt + mSize) where trak.type == "trak" {
        let kids = boxes(d, trak.at + 8, trak.at + trak.size)
        guard let mdia = kids.first(where: { $0.type == "mdia" }),
              let hdlr = boxes(d, mdia.at + 8, mdia.at + mdia.size).first(where: { $0.type == "hdlr" }),
              String(bytes: d[(hdlr.at + 16)..<(hdlr.at + 20)], encoding: .ascii) == "vide",
              let edts = kids.first(where: { $0.type == "edts" }) else { continue }
        put32(&d, trak.at, trak.size - edts.size)
        put32(&d, mAt, mSize - edts.size)
        d.removeSubrange(edts.at..<(edts.at + edts.size))
        try d.write(to: url)
        print("stripped the video track's identity edit list (\(edts.size) bytes) from \(url.lastPathComponent)")
        return
    }
    print("no video edit list in \(url.lastPathComponent)")
}

// MARK: - Finalize (§11.3 as revised): no video edit list, a cover image, `moov` before `mdat`
//
// Works on the writer's layout (ftyp, mdat, moov last). The moov is parsed into a box tree, the video
// track's identity `edts` is dropped, a `udta/meta/ilst/covr` (iTunes cover art, which Finder and Quick
// Look use as the thumbnail) is appended, and the moov is written right after `ftyp`. Everything that
// followed ftyp moves down by the new moov's size, so every `stco`/`co64` entry is shifted by it. The
// media bytes are copied untouched.

private indirect enum Box {
    case leaf(String, Data)                 // type, payload (after the 8-byte header)
    case container(String, Data, [Box])     // type, prefix (e.g. meta's version/flags), children

    var type: String {
        switch self { case .leaf(let t, _), .container(let t, _, _): return t }
    }
    func serialized() -> Data {
        var body = Data()
        switch self {
        case .leaf(_, let p): body = p
        case .container(_, let prefix, let kids):
            body = prefix
            for k in kids { body.append(k.serialized()) }
        }
        var out = Data()
        let size = UInt32(8 + body.count)
        out.append(contentsOf: [UInt8(size >> 24), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)])
        out.append(type.data(using: .isoLatin1)!)
        out.append(body)
        return out
    }
}

private let containerTypes: Set<String> = ["moov", "trak", "mdia", "minf", "stbl", "edts", "udta", "dinf", "ilst"]

private func parseBoxes(_ d: Data, _ start: Int, _ end: Int) throws -> [Box] {
    var out: [Box] = []
    var p = start
    while p + 8 <= end {
        let size = u32(d, p)
        let type = String(bytes: d[(p + 4)..<(p + 8)], encoding: .isoLatin1) ?? "????"
        guard size >= 8, p + size <= end else { throw NSError(domain: "finalize", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad \(type) box at \(p)"]) }
        if containerTypes.contains(type) {
            out.append(.container(type, Data(), try parseBoxes(d, p + 8, p + size)))
        } else if type == "meta" {
            out.append(.container(type, d.subdata(in: (p + 8)..<(p + 12)), try parseBoxes(d, p + 12, p + size)))
        } else {
            out.append(.leaf(type, d.subdata(in: (p + 8)..<(p + size))))
        }
        p += size
    }
    return out
}

/// The track's handler type ("vide", "soun") from mdia/hdlr.
private func handler(_ trak: Box) -> String? {
    guard case .container(_, _, let kids) = trak,
          case .container(_, _, let mdia)? = kids.first(where: { $0.type == "mdia" }),
          case .leaf(_, let hdlr)? = mdia.first(where: { $0.type == "hdlr" }), hdlr.count >= 12 else { return nil }
    return String(bytes: hdlr[hdlr.startIndex + 8..<hdlr.startIndex + 12], encoding: .ascii)
}

/// Applies `f` to every box in the tree (post-order), rebuilding containers.
private func mapBoxes(_ boxes: [Box], _ f: (Box) -> Box?) -> [Box] {
    boxes.compactMap { b in
        switch b {
        case .leaf: return f(b)
        case .container(let t, let prefix, let kids): return f(.container(t, prefix, mapBoxes(kids, f)))
        }
    }
}

private func shiftChunkOffsets(_ b: Box, by delta: Int) -> Box {
    guard case .leaf(let t, var p) = b, t == "stco" || t == "co64" else { return b }
    let n = u32(p, p.startIndex + 4)
    let base = p.startIndex + 8
    for i in 0..<n {
        if t == "stco" {
            let at = base + 4 * i
            let v = u32(p, at) + delta
            precondition(v >= 0 && v < 1 << 32, "chunk offset overflow")
            put32(&p, at, v)
        } else {
            let at = base + 8 * i
            var v = 0
            for k in 0..<8 { v = v << 8 | Int(p[at + k]) }
            v += delta
            for k in 0..<8 { p[at + k] = UInt8((v >> (8 * (7 - k))) & 0xFF) }
        }
    }
    return .leaf(t, p)
}

/// The title written as iTunes `©nam` (fourth cut: the files had cover art but no title).
let movieTitle = "Sill sizzle reel v3.1"

private func coverArt(_ jpeg: Data) -> Box {
    // hdlr: version/flags 0, pre_defined 0, handler 'mdir', reserved 'appl' 0 0, empty name.
    var hdlr = Data(count: 8)
    hdlr.append("mdirappl".data(using: .ascii)!)
    hdlr.append(Data(count: 9))
    // data: type 1 (UTF-8), locale 0, the title.
    var name = Data([0, 0, 0, 1, 0, 0, 0, 0])
    name.append(movieTitle.data(using: .utf8)!)
    // data: type 13 (JPEG), locale 0, the bytes.
    var payload = Data([0, 0, 0, 13, 0, 0, 0, 0])
    payload.append(jpeg)
    let ilst = Box.container("ilst", Data(), [.container("\u{A9}nam", Data(), [.leaf("data", name)]),
                                              .container("covr", Data(), [.leaf("data", payload)])])
    return .container("udta", Data(), [.container("meta", Data(count: 4), [.leaf("hdlr", hdlr), ilst])])
}

func finalizeMP4(_ url: URL, cover: Data?) throws {
    let d = try Data(contentsOf: url)
    var top: [(type: String, at: Int, size: Int)] = []
    var p = 0
    while p + 8 <= d.count {
        var size = u32(d, p)
        let type = String(bytes: d[(p + 4)..<(p + 8)], encoding: .ascii) ?? "????"
        if size == 1 { size = 0; for k in 0..<8 { size = size << 8 | Int(d[p + 8 + k]) } }
        if size == 0 { size = d.count - p }
        top.append((type, p, size))
        p += size
    }
    guard top.first?.type == "ftyp", let moov = top.first(where: { $0.type == "moov" }),
          let mdat = top.first(where: { $0.type == "mdat" }) else {
        throw NSError(domain: "finalize", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent): no ftyp/mdat/moov"])
    }
    guard moov.at > mdat.at else { print("finalize: \(url.lastPathComponent) already has moov first; left as is"); return }
    guard case .container(_, _, var kids)? = try parseBoxes(d, moov.at, moov.at + moov.size).first else {
        throw NSError(domain: "finalize", code: 3)
    }
    // 1. The video track's identity edit list.
    var stripped = 0
    kids = kids.map { b in
        guard b.type == "trak", handler(b) == "vide", case .container(let t, let prefix, let tk) = b else { return b }
        let n = tk.count
        let rest = tk.filter { $0.type != "edts" }
        stripped += n - rest.count
        return .container(t, prefix, rest)
    }
    // 2. Cover art (replacing any udta the writer left).
    if let cover {
        kids.removeAll { $0.type == "udta" }
        kids.append(coverArt(cover))
    }
    // 3. moov first: its new size shifts everything after ftyp.
    let draft = Box.container("moov", Data(), kids).serialized()
    let shifted = mapBoxes(kids) { shiftChunkOffsets($0, by: draft.count) }
    let newMoov = Box.container("moov", Data(), shifted).serialized()
    precondition(newMoov.count == draft.count)
    let ftyp = top[0]
    var out = d.subdata(in: 0..<(ftyp.at + ftyp.size))
    out.append(newMoov)
    for b in top.dropFirst() where b.type != "moov" { out.append(d.subdata(in: b.at..<(b.at + b.size))) }
    let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).finalize")
    try out.write(to: tmp)
    _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    print("finalize: \(url.lastPathComponent): video edts removed \(stripped), cover \(cover?.count ?? 0) bytes, title \"\(cover == nil ? "" : movieTitle)\", moov \(newMoov.count) bytes first, chunk offsets +\(newMoov.count)")
}

/// A JPEG of a PNG (the poster frame), quality 0.9.
func jpegData(fromPNG url: URL) throws -> Data {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw NSError(domain: "finalize", code: 4, userInfo: [NSLocalizedDescriptionKey: "no poster PNG at \(url.path)"])
    }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { throw NSError(domain: "finalize", code: 5) }
    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "finalize", code: 6) }
    return out as Data
}
