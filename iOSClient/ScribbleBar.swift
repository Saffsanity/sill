import Combine
import StreamProtocol
import SwiftUI
import UIKit

/// Observes iOS software keyboard frame notifications to provide automatic keyboard avoidance.
final class KeyboardObserver: ObservableObject {
    static let shared = KeyboardObserver()

    @Published var keyboardHeight: CGFloat = 0
    @Published var isVisible: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .compactMap { notification -> (CGFloat, Double)? in
                guard let userInfo = notification.userInfo,
                      let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return nil
                }
                let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                let screenHeight = UIScreen.main.bounds.height
                let height: CGFloat
                if endFrame.origin.y >= screenHeight {
                    height = 0
                } else {
                    height = max(0, screenHeight - endFrame.origin.y)
                }
                return (height, duration)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] (height, duration) in
                guard let self else { return }
                withAnimation(.easeOut(duration: max(duration, 0.15))) {
                    self.keyboardHeight = height
                    self.isVisible = height > 24
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(.easeOut(duration: max(duration, 0.15))) {
                    self.keyboardHeight = 0
                    self.isVisible = false
                }
            }
            .store(in: &cancellables)
    }

    /// Dismisses any active software keyboard system-wide.
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Which edge of the stream pane the floating input pad is snapped to.
enum ScribbleDockEdge: String, Equatable, CaseIterable {
    case top, bottom, left, right

    var isHorizontalBar: Bool { self == .top || self == .bottom }

    var alignment: Alignment {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    var transitionEdge: Edge {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    var title: String {
        switch self {
        case .top: return "顶部"
        case .bottom: return "底部"
        case .left: return "左侧"
        case .right: return "右侧"
        }
    }

    var symbol: String {
        switch self {
        case .top: return "rectangle.tophalf.inset.filled"
        case .bottom: return "rectangle.bottomhalf.inset.filled"
        case .left: return "rectangle.lefthalf.inset.filled"
        case .right: return "rectangle.righthalf.inset.filled"
        }
    }

    static func nearest(for point: CGPoint, in size: CGSize) -> ScribbleDockEdge {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let x = min(max(point.x, 0), w)
        let y = min(max(point.y, 0), h)
        let distances: [(ScribbleDockEdge, CGFloat)] = [
            (.top, y / h),
            (.bottom, (h - y) / h),
            (.left, x / w),
            (.right, (w - x) / w),
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .bottom
    }
}

/// Tracks live bidirectional text synchronization between the iPad multi-line input box and the Mac's
/// currently focused input field (or highlighted text selection), without any timer-based auto-send.
private final class ScribbleSyncEngine: ObservableObject {
    /// What we believe the Mac's current text (or current replacement of a selection) holds.
    var macMirroredText: String = ""
    /// True when the Mac started with a highlighted text selection (`kAXSelectedTextAttribute`), so the very
    /// first edit from the iPad replaces that selection before switching to incremental suffix diffs.
    var hasPendingSelectionOverwrite: Bool = false
    /// Last Mac revision we absorbed, preventing duplicate resets.
    var lastAbsorbedRevision: UInt64 = 0
    /// Last Mac focus ID we absorbed.
    var lastAbsorbedFocusID: UInt64 = 0
    /// When the user last edited locally on iPad (guards against out-of-order network echoes).
    var lastLocalEditAt: TimeInterval = 0
    private var pendingReconcileWork: DispatchWorkItem?

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    func absorbFromMac(value: String?, isSelection: Bool, focusID: UInt64, revision: UInt64, force: Bool) -> String? {
        let isNewFocus = (focusID != lastAbsorbedFocusID)
        let isNewRevision = (revision != lastAbsorbedRevision)
        guard force || isNewFocus || isNewRevision else { return nil }

        let incoming = Self.normalize(value ?? "")
        let isFieldCleared = incoming.isEmpty && !macMirroredText.isEmpty

        let now = ProcessInfo.processInfo.systemUptime
        // When a message is sent on Mac, the field clears. Never suppress or delay clearing!
        if !force && !isNewFocus && !isFieldCleared && (now - lastLocalEditAt) < 0.30 {
            return nil
        }

        // Moving the Mac caret mid-text (e.g. via arrow keys) causes CursorShapeWatcher to report
        // syncedText = nil (whereas clearing the field reports ""). Preserve the iPad multi-line draft
        // on same-focus nil transitions unless forced on open/focus switch.
        if !force && !isNewFocus && value == nil && !isSelection && !macMirroredText.isEmpty {
            lastAbsorbedRevision = revision
            return nil
        }

        pendingReconcileWork?.cancel()
        pendingReconcileWork = nil
        lastAbsorbedFocusID = focusID
        lastAbsorbedRevision = revision
        macMirroredText = incoming
        hasPendingSelectionOverwrite = isSelection && !incoming.isEmpty
        return incoming
    }

    func scheduleReconcile(after delay: TimeInterval = 0.35, perform: @escaping () -> Void) {
        pendingReconcileWork?.cancel()
        let item = DispatchWorkItem(block: perform)
        pendingReconcileWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    deinit {
        pendingReconcileWork?.cancel()
    }

    /// Computes and sends the minimal real-time keystrokes/text to synchronize `newText` onto the Mac.
    func applyLocalEdit(newText rawText: String, sendInput: (InputEvent) -> Void) {
        let newText = Self.normalize(rawText)
        guard newText != macMirroredText else { return }
        lastLocalEditAt = ProcessInfo.processInfo.systemUptime

        // If the Mac has a highlighted selection and the user just wrote or cleared in the input box,
        // the first action replaces the entire highlighted selection on the Mac.
        if hasPendingSelectionOverwrite {
            hasPendingSelectionOverwrite = false
            if newText.isEmpty {
                sendBackspace(count: 1, sendInput: sendInput)
            } else {
                sendInput(.text(newText))
            }
            macMirroredText = newText
            return
        }

        let oldChars = Array(macMirroredText)
        let newChars = Array(newText)
        var commonPrefix = 0
        let minLen = min(oldChars.count, newChars.count)
        while commonPrefix < minLen && oldChars[commonPrefix] == newChars[commonPrefix] {
            commonPrefix += 1
        }

        let deletesNeeded = oldChars.count - commonPrefix
        let suffixToInsert = String(newChars[commonPrefix...])

        if deletesNeeded > 0 {
            sendBackspace(count: deletesNeeded, sendInput: sendInput)
        }
        if !suffixToInsert.isEmpty {
            sendInput(.text(suffixToInsert))
        }
        macMirroredText = newText
    }

    func resetAfterEnter() {
        lastLocalEditAt = ProcessInfo.processInfo.systemUptime
        macMirroredText = ""
        hasPendingSelectionOverwrite = false
    }

    func sendBackspace(count: Int, sendInput: (InputEvent) -> Void) {
        guard count > 0 else { return }
        for _ in 0..<count {
            sendInput(.key(hidUsage: 0x2A, down: true, modifiers: 0))
            sendInput(.key(hidUsage: 0x2A, down: false, modifiers: 0))
        }
    }
}

/// Spacious floating multi-line input pad supporting Apple Pencil Scribble, software/hardware keyboards,
/// Mac-repeated arrow keys, and drag-to-snap docking on all four edges (top, bottom, left, right).
struct ScribbleBar: View {
    @Binding var isShown: Bool
    @Binding var autoActivate: Bool
    @Binding var hasDraft: Bool
    @Binding var isTextFocused: Bool
    @Binding var dockEdge: ScribbleDockEdge
    let macFocused: Bool
    let macFocusID: UInt64
    let macSyncedText: String?
    let macTextIsSelection: Bool
    let macTextRevision: UInt64
    let panelSize: CGSize
    let onDismiss: () -> Void
    let sendInput: (InputEvent) -> Void

    @State private var text: String = ""
    @State private var shiftLatched: Bool = false
    @State private var commandLatched: Bool = false
    @State private var heldArrow = HeldCap()
    @State private var dragOffset: CGSize = .zero
    @State private var snapPreviewEdge: ScribbleDockEdge? = nil
    @StateObject private var syncEngine = ScribbleSyncEngine()
    @ObservedObject private var keyboard = KeyboardObserver.shared

    private var activeEdge: ScribbleDockEdge { snapPreviewEdge ?? dockEdge }

    /// Generous multi-line editor height adapted to top/bottom vs left/right side docking.
    private var canvasHeight: CGFloat {
        let h = panelSize.height > 0 ? panelSize.height : 640
        if dockEdge.isHorizontalBar {
            if dockEdge == .bottom && keyboard.isVisible {
                // Adaptive height when software keyboard is open, so input box fits nicely above keyboard
                let available = max(90, panelSize.height - keyboard.keyboardHeight - 110)
                return min(160, available)
            }
            return min(240, max(124, h * 0.34))
        } else {
            return min(420, max(168, h * 0.56))
        }
    }

    /// Side-docked width when snapped to left or right edge.
    private var sidePanelWidth: CGFloat {
        let w = panelSize.width > 0 ? panelSize.width : 1024
        return min(348, max(252, w * 0.34))
    }

    private var shadowOffsetY: CGFloat {
        switch dockEdge {
        case .top: return 6
        case .bottom: return -6
        case .left, .right: return 4
        }
    }

    private var effectiveYOffset: CGFloat {
        if dockEdge == .bottom {
            return dragOffset.height - keyboard.keyboardHeight
        } else {
            return dragOffset.height
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandleBar
            headerBar
            Divider().background(Color.white.opacity(0.10))
            writingCanvas
        }
        .frame(maxWidth: dockEdge.isHorizontalBar ? .infinity : sidePanelWidth)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.09, green: 0.10, blue: 0.12).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            snapPreviewEdge != nil
                                ? Color(red: 0.35, green: 0.78, blue: 0.98).opacity(0.85)
                                : (macTextIsSelection
                                    ? Color(red: 0.98, green: 0.78, blue: 0.32).opacity(0.65)
                                    : (macFocused
                                        ? Color(red: 0.35, green: 0.78, blue: 0.98).opacity(0.50)
                                        : Color.white.opacity(0.20))),
                            lineWidth: snapPreviewEdge != nil ? 1.8 : 1.2
                        )
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: shadowOffsetY)
        .padding(.horizontal, dockEdge.isHorizontalBar ? 16 : 0)
        .padding(.leading, dockEdge == .left ? 12 : 0)
        .padding(.trailing, dockEdge == .right ? 12 : 0)
        .padding(.top, dockEdge == .top ? 12 : (dockEdge.isHorizontalBar ? 0 : 12))
        .padding(.bottom, dockEdge == .bottom ? 12 : (dockEdge.isHorizontalBar ? 0 : 12))
        .offset(x: dragOffset.width, y: effectiveYOffset)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: keyboard.keyboardHeight)
        .onAppear {
            if let initial = syncEngine.absorbFromMac(
                value: macSyncedText,
                isSelection: macTextIsSelection,
                focusID: macFocusID,
                revision: macTextRevision,
                force: true
            ) {
                text = initial
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFocused = true
            }
        }
        .onChange(of: macFocusID) { _, newFocusID in
            if let updated = syncEngine.absorbFromMac(
                value: macSyncedText,
                isSelection: macTextIsSelection,
                focusID: newFocusID,
                revision: macTextRevision,
                force: true
            ) {
                text = updated
            }
        }
        .onChange(of: macTextRevision) { _, newRev in
            reconcileFromMac(revision: newRev)
        }
        .onChange(of: macSyncedText) { _, newText in
            if let newText, newText.isEmpty && !text.isEmpty {
                // Mac text field became empty (e.g. message was sent on Mac): clear local input
                text = ""
                syncEngine.resetAfterEnter()
            } else if let newText, !newText.isEmpty && text != newText {
                reconcileFromMac(revision: macTextRevision)
            }
        }
        .onChange(of: text, initial: true) { _, newValue in
            hasDraft = !newValue.isEmpty
        }
        .onDisappear {
            releaseAllHeldArrows()
            isTextFocused = false
            hasDraft = false
        }
    }

    private func reconcileFromMac(revision: UInt64) {
        if let updated = syncEngine.absorbFromMac(
            value: macSyncedText,
            isSelection: macTextIsSelection,
            focusID: macFocusID,
            revision: revision,
            force: false
        ) {
            text = updated
        } else if revision != syncEngine.lastAbsorbedRevision {
            syncEngine.scheduleReconcile {
                reconcileFromMac(revision: macTextRevision)
            }
        }
    }

    /// Top grabber strip: drag anywhere here (or on the header title) to snap to top, bottom, left, or right.
    private var dragHandleBar: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(snapPreviewEdge != nil ? 0.65 : 0.30))
                .frame(width: 44, height: 4)
            if let preview = snapPreviewEdge {
                Text("松手吸附\(preview.title)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.35, green: 0.78, blue: 0.98))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 18)
        .contentShape(Rectangle())
        .gesture(dockDragGesture)
    }

    private var dockDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("scribbleHost"))
            .onChanged { value in
                dragOffset = value.translation
                if hypot(value.translation.width, value.translation.height) >= 24 {
                    snapPreviewEdge = ScribbleDockEdge.nearest(for: value.location, in: panelSize)
                } else {
                    snapPreviewEdge = nil
                }
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                let projected = CGPoint(
                    x: value.location.x + value.velocity.width * 0.06,
                    y: value.location.y + value.velocity.height * 0.06
                )
                let target = distance >= 24
                    ? ScribbleDockEdge.nearest(for: projected, in: panelSize)
                    : dockEdge
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    dockEdge = target
                    dragOffset = .zero
                    snapPreviewEdge = nil
                }
            }
    }

    @ViewBuilder
    private var headerBar: some View {
        if dockEdge.isHorizontalBar {
            HStack(spacing: 8) {
                titleCluster
                    .contentShape(Rectangle())
                    .gesture(dockDragGesture)

                Spacer(minLength: 4)

                toolbarScrollView
                    .frame(maxWidth: .infinity, alignment: .trailing)

                closeButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 8)
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    titleCluster
                        .contentShape(Rectangle())
                        .gesture(dockDragGesture)
                    Spacer(minLength: 4)
                    closeButton
                }
                toolbarScrollView
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }

    private var titleCluster: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.35, green: 0.78, blue: 0.98))

            Text("手写/键盘")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))

            if macTextIsSelection {
                Text("已同步选中")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.98, green: 0.82, blue: 0.36))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(red: 0.98, green: 0.78, blue: 0.32).opacity(0.18)))
            } else if macFocused {
                Text(macSyncedText != nil ? "实时同步" : "实时输入")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.90, blue: 0.62))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(red: 0.42, green: 0.90, blue: 0.62).opacity(0.16)))
            }
        }
    }

    private var toolbarScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if keyboard.isVisible {
                    Button(action: { keyboard.dismissKeyboard() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 11, weight: .bold))
                            Text("收起键盘")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(Color(red: 0.98, green: 0.35, blue: 0.35).opacity(0.85))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("收起软键盘，使用 Apple Pencil 手写")
                }

                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        dockEdge = (dockEdge == .bottom ? .top : .bottom)
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: dockEdge == .bottom ? "arrow.up.to.line" : "arrow.down.to.line")
                            .font(.system(size: 11, weight: .bold))
                        Text(dockEdge == .bottom ? "移至顶部" : "移至底部")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.88))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("快速翻转吸附到顶部或底部")

                pillToggle(
                    title: "键盘",
                    symbol: "keyboard",
                    active: isTextFocused,
                    action: { isTextFocused.toggle() }
                )

                pillToggle(
                    title: autoActivate ? "自动" : "手动",
                    symbol: nil,
                    active: autoActivate,
                    action: { autoActivate.toggle() }
                )

                dockMenuButton

                arrowCluster

                iconButton(
                    symbol: "delete.left",
                    label: "退格删除",
                    action: handleBackspaceButton
                )

                modifierButton(
                    title: "⇧",
                    active: shiftLatched,
                    action: { shiftLatched.toggle() }
                )

                modifierButton(
                    title: "⌘",
                    active: commandLatched,
                    action: { commandLatched.toggle() }
                )

                actionKeyButton(
                    title: "换行",
                    accent: false,
                    action: { triggerReturn(shift: true, command: false) }
                )

                actionKeyButton(
                    title: "⌘↵",
                    accent: false,
                    action: { triggerReturn(shift: false, command: true) }
                )

                actionKeyButton(
                    title: enterButtonTitle,
                    accent: true,
                    action: {
                        triggerReturn(shift: shiftLatched, command: commandLatched)
                        shiftLatched = false
                        commandLatched = false
                    }
                )

                if !text.isEmpty {
                    iconButton(
                        symbol: "trash",
                        label: "清空当前文字",
                        action: {
                            text = ""
                            syncEngine.applyLocalEdit(newText: "", sendInput: sendInput)
                        }
                    )
                }
            }
        }
    }

    private var dockMenuButton: some View {
        Menu {
            ForEach(ScribbleDockEdge.allCases, id: \.self) { edge in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        dockEdge = edge
                    }
                } label: {
                    Label("吸附\(edge.title)", systemImage: edge.symbol)
                }
            }
        } label: {
            Image(systemName: activeEdge.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.14)))
        }
        .accessibilityLabel("切换吸附位置")
    }

    private var arrowCluster: some View {
        HStack(spacing: 4) {
            heldArrowButton(symbol: "arrow.left", usage: 0x50, label: "左方向键")
            heldArrowButton(symbol: "arrow.up", usage: 0x52, label: "上方向键")
            heldArrowButton(symbol: "arrow.down", usage: 0x51, label: "下方向键")
            heldArrowButton(symbol: "arrow.right", usage: 0x4F, label: "右方向键")
        }
    }

    private func heldArrowButton(symbol: String, usage: UInt16, label: String) -> some View {
        Button {
            let events = heldArrow.activated(usage, latched: activeModifiers, at: ProcessInfo.processInfo.systemUptime)
            if HeldCap.spendsLatch(events) { clearLatchedModifiers() }
            for event in events { sendInput(event) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.16)))
        }
        .buttonStyle(ScribbleHeldKeyStyle { isPressed in
            let now = ProcessInfo.processInfo.systemUptime
            let events = isPressed
                ? heldArrow.touchDown(usage, latched: activeModifiers, at: now)
                : heldArrow.touchUp(usage, at: now)
            if isPressed && HeldCap.spendsLatch(events) { clearLatchedModifiers() }
            for event in events { sendInput(event) }
        })
        .accessibilityLabel(label)
    }

    private var closeButton: some View {
        Button {
            isTextFocused = false
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("隐藏输入框")
    }

    private var activeModifiers: KeyModifiers {
        var mods: KeyModifiers = []
        if shiftLatched { mods.insert(.shift) }
        if commandLatched { mods.insert(.command) }
        return mods
    }

    private func clearLatchedModifiers() {
        shiftLatched = false
        commandLatched = false
    }

    private func releaseAllHeldArrows() {
        for event in heldArrow.releaseAll() {
            sendInput(event)
        }
    }

    private var enterButtonTitle: String {
        switch (shiftLatched, commandLatched) {
        case (false, false): return "↵ Enter"
        case (true, false):  return "⇧↵ 换行"
        case (false, true):  return "⌘↵ 发送"
        case (true, true):   return "⇧⌘↵"
        }
    }

    private var writingCanvas: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Spacer()
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.75)
                Spacer()
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.75)
                Spacer()
            }
            .padding(.horizontal, 14)
            .allowsHitTesting(false)

            if text.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Apple Pencil 手写，或点击直接用键盘多行输入")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                    Text("支持上下滚动多行内容 · 方向键控光标 · 拖拽顶部可四边吸附")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
            }

            ScribbleTextView(
                text: $text,
                isFocused: $isTextFocused,
                onUserTextChanged: { updated in
                    syncEngine.applyLocalEdit(newText: updated, sendInput: sendInput)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: canvasHeight)
        }
        .frame(height: canvasHeight)
    }

    private func handleBackspaceButton() {
        if !text.isEmpty {
            text.removeLast()
            syncEngine.applyLocalEdit(newText: text, sendInput: sendInput)
        } else {
            syncEngine.sendBackspace(count: 1, sendInput: sendInput)
        }
    }

    /// Sends Return (`0x28`) with optional Shift (`0xE1`) and/or Command (`0xE3`) modifiers using
    /// `KeyChord.press` so Mac apps see genuine modifier key-down/key-up events around Return.
    private func triggerReturn(shift: Bool, command: Bool) {
        // Ensure any un-synced text is flushed before pressing Return
        if text != syncEngine.macMirroredText {
            syncEngine.applyLocalEdit(newText: text, sendInput: sendInput)
        }
        var mods: KeyModifiers = []
        if shift { mods.insert(.shift) }
        if command { mods.insert(.command) }
        for event in KeyChord.press(0x28, with: mods) {
            sendInput(event)
        }
        if shift && !command {
            // Shift+Enter inserts a line break inside most chat/editor boxes: keep a newline locally
            text.append("\n")
            syncEngine.macMirroredText = text
            syncEngine.lastLocalEditAt = ProcessInfo.processInfo.systemUptime
        } else {
            // Enter or Cmd+Enter typically submits/commits the input field: clear local buffer
            // (if the Mac field actually kept the text, the next AX sync revision will mirror it back).
            text = ""
            syncEngine.resetAfterEnter()
        }
    }

    private func pillToggle(title: String, symbol: String?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(active ? Color.black : Color.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(active ? Color(red: 0.35, green: 0.78, blue: 0.98) : Color.white.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
    }

    private func modifierButton(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.90))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? Color(red: 0.98, green: 0.78, blue: 0.32) : Color.white.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
    }

    private func actionKeyButton(title: String, accent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent ? Color.black : Color.white.opacity(0.92))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accent ? Color(red: 0.35, green: 0.78, blue: 0.98) : Color.white.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
    }

    private func iconButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ScribbleHeldKeyStyle: ButtonStyle {
    let pressed: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .onChange(of: configuration.isPressed) { _, isPressed in
                pressed(isPressed)
            }
    }
}

private struct ScribbleTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onUserTextChanged: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.textColor = .white
        tv.tintColor = UIColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1.0)
        tv.font = .systemFont(ofSize: 17, weight: .regular)
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        tv.keyboardAppearance = .dark
        tv.keyboardType = .default
        tv.returnKeyType = .default
        tv.isEditable = true
        tv.isSelectable = true
        tv.isUserInteractionEnabled = true
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.showsVerticalScrollIndicator = true
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.inlinePredictionType = .no
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text && uiView.markedTextRange == nil {
            context.coordinator.isProgrammaticUpdate = true
            uiView.text = text
            // Place caret at the end of the synchronized text and scroll so new lines are visible
            let endPos = uiView.endOfDocument
            uiView.selectedTextRange = uiView.textRange(from: endPos, to: endPos)
            let endOffset = (uiView.text as NSString).length
            uiView.scrollRangeToVisible(NSRange(location: endOffset, length: 0))
            context.coordinator.isProgrammaticUpdate = false
        }

        if isFocused && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                if self.isFocused && uiView.window != nil && !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                }
            }
        } else if !isFocused && uiView.isFirstResponder {
            DispatchQueue.main.async {
                if !self.isFocused && uiView.isFirstResponder {
                    uiView.resignFirstResponder()
                }
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScribbleTextView
        var isProgrammaticUpdate = false

        init(_ parent: ScribbleTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                if !self.parent.isFocused {
                    self.parent.isFocused = true
                }
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                if self.parent.isFocused {
                    self.parent.isFocused = false
                }
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate, textView.markedTextRange == nil else { return }
            let current = textView.text ?? ""
            parent.text = current
            parent.onUserTextChanged(current)
            let sel = textView.selectedRange
            textView.scrollRangeToVisible(sel)
        }
    }
}
