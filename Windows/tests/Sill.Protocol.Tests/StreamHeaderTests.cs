using Sill.Protocol;

namespace Sill.Protocol.Tests;

public class StreamHeaderTests
{
    // A frame (kind 1) at timestamp 1.5, a keyframe, with a 3-byte payload, as the Swift
    // StreamMessage.serialized() writes it: 1.5's bits are 0x3FF8000000000000.
    private static readonly byte[] SwiftFrame =
    [
        0x01,
        0x3F, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x01,
        0x00, 0x00, 0x00, 0x03,
        0xAA, 0xBB, 0xCC,
    ];

    [Fact]
    public void ParsesTheSwiftLayout()
    {
        var h = StreamHeader.Parse(SwiftFrame);
        Assert.Equal(1, h.Kind);
        Assert.Equal(1.5, h.Timestamp);
        Assert.True(h.IsKeyframe);
        Assert.Equal(3u, h.PayloadLength);
    }

    [Fact]
    public void SerializesTheSwiftLayout()
    {
        byte[] bytes = StreamHeader.Serialize(1, 1.5, true, new byte[] { 0xAA, 0xBB, 0xCC });
        Assert.Equal(SwiftFrame, bytes);
    }

    [Theory]
    [InlineData(0, false)]
    [InlineData(1, true)]
    [InlineData(2, false)]
    [InlineData(255, false)]
    public void OnlyTheByteOneIsAKeyframe(byte flag, bool expected)
    {
        var bytes = (byte[])SwiftFrame.Clone();
        bytes[9] = flag;
        Assert.Equal(expected, StreamHeader.Parse(bytes).IsKeyframe);
    }

    [Fact]
    public void KeepsAnUnknownKind()
    {
        var bytes = (byte[])SwiftFrame.Clone();
        bytes[0] = 200;
        Assert.Equal(200, StreamHeader.Parse(bytes).Kind);
    }

    [Fact]
    public void ReadsTheLengthBigEndian()
    {
        var bytes = (byte[])SwiftFrame.Clone();
        bytes[10] = 0x01; bytes[11] = 0x02; bytes[12] = 0x03; bytes[13] = 0x04;
        Assert.Equal(0x01020304u, StreamHeader.Parse(bytes).PayloadLength);
    }

    [Fact]
    public void RefusesAShortHeader() =>
        Assert.Throws<ArgumentException>(() => StreamHeader.Parse(SwiftFrame.AsSpan(0, 13)));

    [Fact]
    public void RoundTrips()
    {
        var h = new StreamHeader(16, 1_760_000_000.25, false, 4096);
        var bytes = new byte[StreamHeader.Length];
        h.Write(bytes);
        Assert.Equal(h, StreamHeader.Parse(bytes));
    }
}
