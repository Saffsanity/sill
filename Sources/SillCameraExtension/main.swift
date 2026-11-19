// Sill Camera: the Core Media I/O camera extension that lets apps on this Mac use the camera of an iPhone or iPad
// sharing it with Sill (docs/camera-plan.md §6.4, §7). Packaged by Scripts/make-app.sh into
// Sill.app/Contents/Library/SystemExtensions/me.saffer.sill.mac.camera.systemextension (with SILL_CAMERA_EXTENSION=1),
// activated by Sill for Mac from /Applications once an administrator allows it, and run by macOS as its own
// sandboxed process. Nothing here runs in a test.
#if os(macOS)
import CoreMediaIO
import Foundation

/// Sill Camera's one queue (SillCameraProvider's header says what runs on it).
let feedQueue = DispatchQueue(label: "sill.camera.feed", qos: .userInteractive)
let sillCamera = SillCameraProvider(queue: feedQueue)
CMIOExtensionProvider.startService(provider: sillCamera.provider)
CFRunLoopRun()
#endif
