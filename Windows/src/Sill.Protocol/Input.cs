using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Sill.Protocol;

/// <summary>
/// Kind 8: input aimed at the streamed source, as Swift's synthesized <c>InputEvent</c> encodes it
/// (Sources/StreamProtocol/Input.swift). Positions are fractions of the video frame (0…1).
/// </summary>
public static class InputMessages
{
    public const byte Kind = 8;

    /// <summary>CGEventFlags bits, which the host reads from a key's <c>modifiers</c>.</summary>
    public const ulong Shift = 0x20000, Control = 0x40000, Option = 0x80000, Command = 0x100000;

    public enum Pointer { Move, LeftDown, LeftUp, RightDown, RightUp }

    /// <summary><c>{"pointer":{"_0":"leftDown","x":0.5,"y":0.25}}</c></summary>
    public static byte[] PointerEvent(Pointer action, double x, double y)
    {
        string name = action switch
        {
            Pointer.Move => "move", Pointer.LeftDown => "leftDown", Pointer.LeftUp => "leftUp",
            Pointer.RightDown => "rightDown", _ => "rightUp",
        };
        return Message($$$"""{"pointer":{"_0":"{{{name}}}","x":{{{N(x)}}},"y":{{{N(y)}}}}}""");
    }

    /// <summary>A scroll with the pointer at (x, y); dx, dy are fractions of the frame the content
    /// moves, natural sign (positive dy: the content moves down, as a wheel turned up does).</summary>
    public static byte[] Scroll(double x, double y, double dx, double dy) =>
        Message($$$"""{"scroll":{"x":{{{N(x)}}},"y":{{{N(y)}}},"dx":{{{N(dx)}}},"dy":{{{N(dy)}}}}}""");

    public enum ScrollPhase { Began, Ended, MomentumBegan, MomentumEnded }

    /// <summary><c>{"scrollGesture":{"_0":"began","x":0.5,"y":0.5}}</c>: the brackets around a run
    /// of scroll deltas that make the Mac treat them as a trackpad gesture (Input.swift).</summary>
    public static byte[] ScrollGesture(ScrollPhase phase, double x, double y)
    {
        string name = phase switch
        {
            ScrollPhase.Began => "began", ScrollPhase.Ended => "ended",
            ScrollPhase.MomentumBegan => "momentumBegan", _ => "momentumEnded",
        };
        return Message($$$"""{"scrollGesture":{"_0":"{{{name}}}","x":{{{N(x)}}},"y":{{{N(y)}}}}}""");
    }

    /// <summary>A key by USB HID usage (page 7) with the modifiers held, CGEventFlags bits.</summary>
    public static byte[] Key(ushort hidUsage, bool down, ulong modifiers) =>
        Message($$$"""{"key":{"hidUsage":{{{hidUsage}}},"down":{{{(down ? "true" : "false")}}},"modifiers":{{{modifiers}}}}}""");

    /// <summary>Text typed as Unicode (the host types it whatever the Mac's layout).</summary>
    public static byte[] Text(string text) =>
        Message($$$"""{"text":{"_0":{{{JsonSerializer.Serialize(text)}}}}}""");

    private static string N(double v) => Math.Round(v, 5).ToString("0.#####", CultureInfo.InvariantCulture);

    private static byte[] Message(string json) => StreamHeader.Serialize(Kind, 0, false, Encoding.UTF8.GetBytes(json));
}

/// <summary>
/// A PC keyboard's keys as USB HID usages, the host's key codes (KeyStrokes.swift). Windows
/// virtual-key codes in, page-7 usages out; 0 for a key with no Mac counterpart.
/// </summary>
public static class HidKeys
{
    public const ushort LeftControl = 0xE0, LeftShift = 0xE1, LeftOption = 0xE2, LeftCommand = 0xE3,
        RightControl = 0xE4, RightShift = 0xE5, RightOption = 0xE6, RightCommand = 0xE7;

    public static ushort FromVirtualKey(int vk) => vk switch
    {
        >= 0x41 and <= 0x5A => (ushort)(0x04 + vk - 0x41),     // A–Z
        >= 0x31 and <= 0x39 => (ushort)(0x1E + vk - 0x31),     // 1–9
        0x30 => 0x27,                                           // 0
        0x0D => 0x28, 0x1B => 0x29, 0x08 => 0x2A, 0x09 => 0x2B, 0x20 => 0x2C,   // Return, Esc, Backspace, Tab, Space
        0xBD => 0x2D, 0xBB => 0x2E, 0xDB => 0x2F, 0xDD => 0x30, 0xDC => 0x31,   // - = [ ] \
        0xBA => 0x33, 0xDE => 0x34, 0xC0 => 0x35, 0xBC => 0x36, 0xBE => 0x37, 0xBF => 0x38,   // ; ' ` , . /
        0x14 => 0x39,                                           // Caps Lock
        >= 0x70 and <= 0x7B => (ushort)(0x3A + vk - 0x70),     // F1–F12
        0x2D => 0x49, 0x24 => 0x4A, 0x21 => 0x4B, 0x2E => 0x4C, 0x23 => 0x4D, 0x22 => 0x4E,   // Insert Home PgUp Delete End PgDn
        0x27 => 0x4F, 0x25 => 0x50, 0x28 => 0x51, 0x26 => 0x52,                   // → ← ↓ ↑
        >= 0x60 and <= 0x69 => vk == 0x60 ? (ushort)0x62 : (ushort)(0x59 + vk - 0x61),   // keypad 0–9
        0x6A => 0x55, 0x6B => 0x57, 0x6D => 0x56, 0x6E => 0x63, 0x6F => 0x54,     // keypad * + - . /
        _ => 0,
    };
}
