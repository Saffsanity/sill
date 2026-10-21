using System.Text;
using System.Text.Json;
using Sill.Protocol;

namespace Sill.Protocol.Tests;

// Kind 8 as Swift's synthesized InputEvent encodes it (the shapes Scripts/sillclient.py sends).
public class InputTests
{
    private static string Json(byte[] message)
    {
        Assert.Equal(InputMessages.Kind, message[0]);
        Assert.Equal((uint)(message.Length - StreamHeader.Length), StreamHeader.Parse(message).PayloadLength);
        string json = Encoding.UTF8.GetString(message, StreamHeader.Length, message.Length - StreamHeader.Length);
        using var _ = JsonDocument.Parse(json);   // valid JSON
        return json;
    }

    [Fact]
    public void PointersAreSwiftsShape()
    {
        Assert.Equal("""{"pointer":{"_0":"move","x":0.25,"y":0.5}}""", Json(InputMessages.PointerEvent(InputMessages.Pointer.Move, 0.25, 0.5)));
        Assert.Equal("""{"pointer":{"_0":"leftDown","x":0,"y":1}}""", Json(InputMessages.PointerEvent(InputMessages.Pointer.LeftDown, 0, 1)));
        Assert.Equal("""{"pointer":{"_0":"rightUp","x":0.33333,"y":0.1}}""", Json(InputMessages.PointerEvent(InputMessages.Pointer.RightUp, 1 / 3.0, 0.1)));
    }

    [Fact]
    public void ScrollKeyAndTextAreSwiftsShape()
    {
        Assert.Equal("""{"scroll":{"x":0.5,"y":0.5,"dx":0,"dy":-0.04}}""", Json(InputMessages.Scroll(0.5, 0.5, 0, -0.04)));
        Assert.Equal("""{"key":{"hidUsage":44,"down":true,"modifiers":1048576}}""", Json(InputMessages.Key(44, true, InputMessages.Command)));
        // Escaping may differ from Swift's (""" for a quote); the decoded text may not.
        using var text = JsonDocument.Parse(Json(InputMessages.Text("hé \"")));
        Assert.Equal("hé \"", text.RootElement.GetProperty("text").GetProperty("_0").GetString());
    }

    [Theory]
    [InlineData(0x41, 0x04)]   // A
    [InlineData(0x5A, 0x1D)]   // Z
    [InlineData(0x31, 0x1E)]   // 1
    [InlineData(0x30, 0x27)]   // 0
    [InlineData(0x0D, 0x28)]   // Return
    [InlineData(0x20, 0x2C)]   // Space
    [InlineData(0x70, 0x3A)]   // F1
    [InlineData(0x7B, 0x45)]   // F12
    [InlineData(0x26, 0x52)]   // ↑
    [InlineData(0x2E, 0x4C)]   // Delete (forward)
    [InlineData(0x60, 0x62)]   // keypad 0
    [InlineData(0x61, 0x59)]   // keypad 1
    [InlineData(0xFF, 0x00)]   // nothing
    public void VirtualKeysBecomeHidUsages(int vk, int hid) => Assert.Equal((ushort)hid, HidKeys.FromVirtualKey(vk));
}
