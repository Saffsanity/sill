import SwiftUI
import UIKit

/// Settings' App Icon group, its pictures (AppIconChoice; Noah, 2026-11-18; docs/app-icons-plan.md): each icon
/// Sill ships, its picture (the document's Default look, Scripts/app-icon-previews.sh) over its word, the
/// community's with its credit, the one the Home Screen shows marked with a ring and a check. A tap asks iOS for
/// that icon (`UIApplication.setAlternateIconName`), and iOS confirms the change with its own alert; nothing else
/// changes it. The original comes first and stays there, one tap away. In this device's part of Settings, beside
/// the version (HostSettingsPanel's `appIcon`, which gives it the group's title and footnote); its pictures wrap
/// to more rows when more icons come.
///
/// DEBUG `-SillAppIcon original|community|<name>`: the harness's stand-in for iOS's alternate icon name (an
/// unknown name too, as iOS could hand one back), so a photo shows each mark without a change; a tap then moves
/// the stand-in alone. `-SillAppIconFailed 1`: the refusal's line, as though iOS had said no.
struct AppIconPicker: View {
    /// iOS's alternate icon name (nil: the primary icon), read when the group appears and when Sill comes back to
    /// the front (a change made while Settings was open elsewhere).
    @State private var name: String? = AppIconPicker.currentName()
    /// A change iOS has not answered yet: the pictures wait for it.
    @State private var changing = false
    /// iOS did not change the icon: the orange line under the pictures, until the next tap.
    @State private var failed = AppIconPicker.startsFailed
    /// The picture's side: 60 pt at the standard text size, growing with it to 96 pt (the previews' 288 pixels
    /// at 3x), so at the accessibility sizes the words grow and the pictures stay whole on a phone.
    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 60
    private var side: CGFloat { min(scaledSide, 96) }
    /// A picture's column: room for its word at the footnote's size ("Community"), and never narrower than the
    /// picture and its ring. At the accessibility sizes two no longer fit side by side on a phone: they stack.
    @ScaledMetric(relativeTo: .footnote) private var scaledColumn: CGFloat = 92
    private var column: CGFloat { max(scaledColumn, side + 20) }

    /// Whether Settings shows the group: where iOS can change this app's icon.
    static var offered: Bool {
        AppIconChoice.offered(supportsAlternateIcons: UIApplication.shared.supportsAlternateIcons)
    }

    var body: some View {
        let current = AppIconChoice.current(alternateIconName: name)
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: column, maximum: column), spacing: 8, alignment: .top)],
                      alignment: .leading, spacing: 14) {
                ForEach(AppIconChoice.allCases) { choice in
                    tile(choice, selected: choice == current)
                }
            }
            if failed {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    Text(AppIconChoice.Copy.failed)
                }
                .font(.footnote)
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            name = Self.currentName()
        }
        #if DEBUG
        .onAppear { print("app icon: \(current.rawValue) shown (\(name.map { "alternate \($0)" } ?? "the primary icon"))") }
        #endif
    }

    /// One icon: its picture, ringed and checked when it is Sill's icon now, over its word and credit; one
    /// VoiceOver button, selected when it is the one.
    private func tile(_ choice: AppIconChoice, selected: Bool) -> some View {
        Button { choose(choice) } label: {
            VStack(spacing: 7) {
                Image(choice.previewImageName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
                    .padding(5)
                    .overlay {
                        // The icon's own shape, a little larger: its corners are about a quarter of its side.
                        RoundedRectangle(cornerRadius: side * 0.25 + 5, style: .continuous)
                            .strokeBorder(Palette.accent, lineWidth: 2.5)
                            .opacity(selected ? 1 : 0)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Palette.control, Palette.accent)
                                .font(.system(size: side * 0.3, weight: .semibold))
                                .background(Circle().fill(Palette.control).padding(-2.5))
                                .offset(x: 3, y: 3)
                        }
                    }
                VStack(spacing: 1) {
                    Text(choice.title)
                        .font(.footnote.weight(selected ? .semibold : .regular))
                        .foregroundStyle(Palette.text)
                    if let credit = choice.credit {
                        Text(credit)
                            .font(.caption2)
                            .foregroundStyle(Palette.muted)
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(changing)
        // The button is one element already; its words replace what its picture and lines would say (the
        // picture's asset name among them).
        .accessibilityLabel(choice.spoken)
        .accessibilityHint(AppIconChoice.Copy.hint(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A tap: what AppIconChoice says to ask of iOS, if anything, then iOS's own name again once it answers.
    private func choose(_ choice: AppIconChoice) {
        failed = false
        guard case .set(let target) = AppIconChoice.request(choice, from: name) else { return }
        #if DEBUG
        if Self.standIn != nil {
            Self.standIn = .some(target)
            name = target
            print("app icon: the stand-in now \(target ?? "the primary icon") (no change asked of iOS)")
            return
        }
        #endif
        changing = true
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(target)
            } catch {
                failed = true
                #if DEBUG
                print("app icon: iOS did not change it to \(target ?? "the primary icon"): \(error)")
                #endif
            }
            changing = false
            name = Self.currentName()
        }
    }

    /// iOS's alternate icon name, or the harness's stand-in for it.
    private static func currentName() -> String? {
        #if DEBUG
        if let standIn { return standIn }
        #endif
        return UIApplication.shared.alternateIconName
    }

    #if DEBUG
    /// `-SillAppIcon`'s stand-in: none without it; `original` the primary icon (nil), `community` its alternate,
    /// any other word that name.
    private static var standIn: String?? = {
        guard let word = UserDefaults.standard.string(forKey: "SillAppIcon") else { return nil }
        return .some(AppIconChoice(rawValue: word).map(\.alternateIconName) ?? word)
    }()
    private static let startsFailed = UserDefaults.standard.bool(forKey: "SillAppIconFailed")
    #else
    private static let startsFailed = false
    #endif
}
