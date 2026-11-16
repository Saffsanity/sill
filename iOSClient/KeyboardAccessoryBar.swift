import UIKit
import StreamProtocol

/// Accessory bar attached directly above the native system keyboard (`inputAccessoryView`),
/// providing modifier keys (`⌘`, `⌥`, `⌃`, `⇧`), control keys (`Esc`, `Tab`, `Space`),
/// and a dismiss button.
final class KeyboardAccessoryBar: UIView {
    weak var inputOverlay: InputOverlayView?
    var sendKey: ((InputEvent) -> Void)?
    var onDismiss: (() -> Void)?

    // Buttons
    private var modifierButtons: [UInt64: UIButton] = [:]
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = UIColor(white: 0.16, alpha: 0.98)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Top separator
        let sep = UIView(frame: CGRect(x: 0, y: 0, width: bounds.width, height: 0.5))
        sep.backgroundColor = UIColor(white: 0.35, alpha: 0.8)
        sep.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        addSubview(sep)

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -4),
            stackView.heightAnchor.constraint(equalToConstant: 36)
        ])

        // 1. Esc
        addActionButton(title: "Esc") { [weak self] in
            self?.sendDirectKey(0x29)
        }

        // 2. Tab
        addActionButton(title: "Tab") { [weak self] in
            self?.sendDirectKey(0x2B)
        }

        // 3. Modifier Keys: ⌃ Ctrl, ⌥ Opt, ⌘ Cmd, ⇧ Shift
        addModifierButton(title: "⌃ Ctrl", flag: .control)
        addModifierButton(title: "⌥ Opt", flag: .option)
        addModifierButton(title: "⌘ Cmd", flag: .command)
        addModifierButton(title: "⇧ Shift", flag: .shift)

        // 4. Space
        addActionButton(title: "Space") { [weak self] in
            self?.sendDirectKey(0x2C)
        }

        // 5. Dismiss Keyboard
        let dismissBtn = UIButton(type: .system)
        dismissBtn.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        dismissBtn.tintColor = UIColor(white: 0.85, alpha: 1.0)
        dismissBtn.backgroundColor = UIColor(white: 0.26, alpha: 0.9)
        dismissBtn.layer.cornerRadius = 6
        dismissBtn.widthAnchor.constraint(equalToConstant: 40).isActive = true
        dismissBtn.heightAnchor.constraint(equalToConstant: 32).isActive = true
        dismissBtn.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)
        stackView.addArrangedSubview(dismissBtn)
    }

    private func addActionButton(title: String, action: @escaping () -> Void) {
        let btn = ActionKeyButton(title: title, action: action)
        stackView.addArrangedSubview(btn)
    }

    private func addModifierButton(title: String, flag: KeyModifiers) {
        let btn = UIButton(type: .custom)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(UIColor(white: 0.9, alpha: 1.0), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.backgroundColor = UIColor(white: 0.26, alpha: 0.9)
        btn.layer.cornerRadius = 6
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
        btn.addTarget(self, action: #selector(modifierTapped(_:)), for: .touchUpInside)
        btn.tag = Int(flag.rawValue)
        modifierButtons[flag.rawValue] = btn
        stackView.addArrangedSubview(btn)
    }

    @objc private func modifierTapped(_ sender: UIButton) {
        let flag = KeyModifiers(rawValue: UInt64(sender.tag))
        inputOverlay?.toggleAccessoryModifier(flag)
        updateModifierAppearance()
    }

    @objc private func handleDismiss() {
        onDismiss?()
    }

    private func sendDirectKey(_ hidUsage: UInt16) {
        let mods = inputOverlay?.currentActiveModifiers ?? []
        for event in KeyChord.press(hidUsage, with: mods) {
            sendKey?(event)
        }
        inputOverlay?.consumeLatchedModifiers()
        updateModifierAppearance()
    }

    /// Refresh styling of modifier buttons based on latched/locked states.
    public func updateModifierAppearance() {
        guard let overlay = inputOverlay else { return }
        let latched = overlay.currentLatchedModifiers
        let locked = overlay.currentLockedModifiers

        for (raw, btn) in modifierButtons {
            let flag = KeyModifiers(rawValue: raw)
            let isLocked = locked.contains(flag)
            let isLatched = latched.contains(flag)

            if isLocked {
                btn.backgroundColor = UIColor.systemBlue
                btn.setTitleColor(.white, for: .normal)
                btn.layer.borderWidth = 1.5
                btn.layer.borderColor = UIColor.white.cgColor
            } else if isLatched {
                btn.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.65)
                btn.setTitleColor(.white, for: .normal)
                btn.layer.borderWidth = 0
            } else {
                btn.backgroundColor = UIColor(white: 0.26, alpha: 0.9)
                btn.setTitleColor(UIColor(white: 0.9, alpha: 1.0), for: .normal)
                btn.layer.borderWidth = 0
            }
        }
    }
}

/// Helper button for action keys.
private final class ActionKeyButton: UIButton {
    private let action: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        setTitleColor(UIColor(white: 0.9, alpha: 1.0), for: .normal)
        titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        backgroundColor = UIColor(white: 0.26, alpha: 0.9)
        layer.cornerRadius = 6
        contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        action()
    }
}
