import SwiftUI
import AVFoundation
import VisionKit
import StreamProtocol

/// The embedded code scanner (docs/remote-access-plan.md §7.7, §7.10): VisionKit's
/// DataScannerViewController in the card's viewfinder, never a presentation. It reads QR codes; a
/// sill://pair link goes to `onLink`, anything else shows "That’s not a Sill code." under the
/// viewfinder for 2 s. The person chose to point the camera, so there is no confirmation step.
/// A link arrives each time the scanner finds the code (again, when a scanner is shown anew with
/// the code in view) and each time the person taps it; StreamClient.scanned decides what starts.
///
/// Where the scanner cannot run (the simulator, a device without the Neural Engine it needs), the
/// card goes straight to the typed path; with the camera refused it says so, with Open Settings.
struct CodeScanner: View {
    /// What the viewfinder shows.
    enum Mode: Equatable {
        /// The live scanner (on a device that supports it, with the camera allowed or not yet asked).
        case live
        /// A drawn stand-in: the DEBUG harness, whose simulator has no scanner.
        case placeholder
        /// The camera was refused: the words and Open Settings in the viewfinder's place.
        case denied
    }

    let mode: Mode
    /// A sill://pair link, and whether the person tapped the code rather than the scanner finding it.
    let onLink: (PairLink, _ tapped: Bool) -> Void
    /// A scan failed and the same code is held: the caption says a tap on it tries again.
    var retryNeedsTap = false
    /// The Mac whose code it reads, for the caption and VoiceOver: the home card's names it
    /// ("Point at the code on Mac mini", docs/home-pairing-plan.md §7.7); nil for "your Mac".
    var mac: String? = nil
    @State private var notSill = false
    @State private var notSillToken = 0
    /// The camera as this view knows it. DataScannerViewController never asks by itself (it only
    /// reports itself unavailable until the camera is allowed), so the first live viewfinder asks.
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    /// Whether this device can scan at all; false in the simulator.
    static var isSupported: Bool { DataScannerViewController.isSupported }

    /// The camera as it stands: refused (or restricted) means the typed path and a way to Settings.
    static var cameraDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    /// The mode for this device now.
    static var currentMode: Mode { cameraDenied ? .denied : .live }

    /// Refused, now or just now in answer to this view's own question.
    private var denied: Bool { mode == .denied || (mode == .live && (access == .denied || access == .restricted)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control)
                if denied {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sill can’t use the camera. Enter the code instead, or allow the camera in Settings.")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 44)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else if mode == .live {
                    // Not yet asked: the frame alone while the system's question is up.
                    if access == .authorized {
                        ScannerRepresentable(onPayload: { handle($0, tapped: $1) })
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Frame()
                } else {
                    Frame()
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Palette.muted)
                }
            }
            .accessibilityElement(children: denied ? .contain : .ignore)
            .accessibilityLabel(denied ? "" : mac.map(DiscoveryPolicy.HomeCopy.viewfinderLabel) ?? "Camera. Point it at the code on your Mac.")
            if !denied {
                Text(notSill ? "That’s not a Sill code." : retryNeedsTap ? "Tap the code to try again."
                     : mac.map(DiscoveryPolicy.HomeCopy.viewfinderCaption) ?? "Point at the code on your Mac")
                    .font(.system(size: 13))
                    .foregroundStyle(notSill ? Color.orange : Palette.muted)
                    .accessibilityHidden(!notSill && !retryNeedsTap)
            }
        }
        .task(id: notSillToken) {
            guard notSillToken > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { notSill = false }
        }
        .task {
            // The person opened the scanner, so this is the moment to ask for the camera.
            guard mode == .live, Self.isSupported, access == .notDetermined else { return }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            access = granted ? .authorized : .denied
        }
    }

    private func handle(_ payload: String, tapped: Bool) {
        if case .success(let link) = PairLink.parse(payload) {
            onLink(link, tapped)
        } else if !notSill {
            notSill = true
            notSillToken += 1
            AccessibilityNotification.Announcement("That’s not a Sill code.").post()
        }
    }

    /// The corner marks that say "a code goes here".
    private struct Frame: View {
        var body: some View {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.62
                let rect = CGRect(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2, width: side, height: side)
                let arm = side * 0.18
                Path { p in
                    for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                             (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
                        p.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
                        p.addLine(to: corner)
                        p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
                    }
                }
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .allowsHitTesting(false)
        }
    }
}

/// DataScannerViewController for QR codes, started once the view is on screen and stopped when it
/// leaves.
private struct ScannerRepresentable: UIViewControllerRepresentable {
    /// A code's text, and whether it came from a tap on its highlight.
    let onPayload: (String, Bool) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                                recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                                isPinchToZoomEnabled: true, isGuidanceEnabled: false, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
        if !scanner.isScanning, DataScannerViewController.isAvailable { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onPayload: (String, Bool) -> Void
        init(onPayload: @escaping (String, Bool) -> Void) { self.onPayload = onPayload }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue { onPayload(text, false) }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let code) = item, let text = code.payloadStringValue { onPayload(text, true) }
        }
    }
}
