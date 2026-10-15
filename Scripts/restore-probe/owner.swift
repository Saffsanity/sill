import AppKit

// TEST ONLY. The restore probe's own window (Scripts/restore-probe/run.sh; issue #57): one NSWindow
// titled with a unique token, put where it is told and ordered BEHIND every other window, in an app
// that never activates itself (LSUIElement, and nothing here asks for focus). It stands in for the
// person at the Mac. Commands on stdin, one per line, in CG global points (top-left origin, as
// Accessibility and the window server give them):
//   move X Y      moved on the Mac
//   size W H      resized on the Mac (its top-left kept)
//   frame X Y W H resized on the Mac from another edge or corner (the whole frame given)
//   min W H       the app's minimum size
//   close         the window closes
//   quit
// It answers "ok <command>" after each, and quits by itself after two minutes whatever happens.
// usage: owner TOKEN X Y W H [fixed]   (fixed: a window that cannot be resized)

let a = CommandLine.arguments
let token = a[1]
let x = CGFloat(Double(a[2])!), y = CGFloat(Double(a[3])!), w = CGFloat(Double(a[4])!), h = CGFloat(Double(a[5])!)
let fixed = a.count > 6 && a[6] == "fixed"

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let primaryH = NSScreen.screens.first!.frame.height
func cocoa(_ r: CGRect) -> NSRect { NSRect(x: r.minX, y: primaryH - r.minY - r.height, width: r.width, height: r.height) }
func cg(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height) }

var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
if !fixed { style.insert(.resizable) }
let window = NSWindow(contentRect: .zero, styleMask: style, backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.animationBehavior = .none
window.title = token
window.setFrame(cocoa(CGRect(x: x, y: y, width: w, height: h)), display: false)
window.orderBack(nil)
print("ready \(getpid()) \(window.windowNumber)")
fflush(stdout)

Thread.detachNewThread {
    while let line = readLine() {
        let p = line.split(separator: " ").map(String.init)
        DispatchQueue.main.async {
            let r = cg(window.frame)
            switch p.first {
            case "move": window.setFrame(cocoa(CGRect(x: CGFloat(Double(p[1])!), y: CGFloat(Double(p[2])!), width: r.width, height: r.height)), display: true)
            case "size": window.setFrame(cocoa(CGRect(x: r.minX, y: r.minY, width: CGFloat(Double(p[1])!), height: CGFloat(Double(p[2])!))), display: true)
            case "frame": window.setFrame(cocoa(CGRect(x: CGFloat(Double(p[1])!), y: CGFloat(Double(p[2])!), width: CGFloat(Double(p[3])!), height: CGFloat(Double(p[4])!))), display: true)
            case "min": window.minSize = NSSize(width: Double(p[1])!, height: Double(p[2])!)
            case "close": window.close()
            case "quit": exit(0)
            default: break
            }
            print("ok \(line)")
            fflush(stdout)
        }
    }
    DispatchQueue.main.async { exit(0) }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 120) { exit(0) }
app.run()
