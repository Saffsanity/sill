using System.Buffers.Binary;

namespace Sill.Protocol;

/// <summary>
/// The 14-byte message header, big endian: kind (1), timestamp (8, an IEEE double's bits),
/// keyframe flag (1), payload length (4). Mirrors <c>StreamMessage.serialized()</c> and
/// <c>StreamMessage.parseHeader(_:)</c> in Sources/StreamProtocol/StreamMessage.swift.
/// </summary>
/// <remarks>
/// <see cref="Kind"/> is the raw byte: a kind this build does not know is skipped by the
/// reader, never a reason to stop, so an older client keeps working against a newer host.
/// </remarks>
public readonly record struct StreamHeader(byte Kind, double Timestamp, bool IsKeyframe, uint PayloadLength)
{
    public const int Length = 14;

    // Caps on what a header may announce (StreamMessage.swift): a reader that waits for the
    // announced bytes could otherwise be held, so it refuses more and closes.
    public const int MaxClientPayload = 1 << 20;
    public const int MaxPairingPayload = 4096;
    public const int MaxFramePayload = 32 << 20;
    public const int MaxOtherHostPayload = 4 << 20;

    public static StreamHeader Parse(ReadOnlySpan<byte> data)
    {
        if (data.Length < Length)
            throw new ArgumentException($"A header is {Length} bytes; got {data.Length}.", nameof(data));
        double ts = BitConverter.UInt64BitsToDouble(BinaryPrimitives.ReadUInt64BigEndian(data[1..9]));
        // The Swift reader counts only the byte 1 as a keyframe.
        bool key = data[9] == 1;
        uint len = BinaryPrimitives.ReadUInt32BigEndian(data[10..14]);
        return new StreamHeader(data[0], ts, key, len);
    }

    public void Write(Span<byte> destination)
    {
        if (destination.Length < Length)
            throw new ArgumentException($"A header is {Length} bytes.", nameof(destination));
        destination[0] = Kind;
        BinaryPrimitives.WriteUInt64BigEndian(destination[1..9], BitConverter.DoubleToUInt64Bits(Timestamp));
        destination[9] = IsKeyframe ? (byte)1 : (byte)0;
        BinaryPrimitives.WriteUInt32BigEndian(destination[10..14], PayloadLength);
    }

    /// <summary>A whole message: this header, then the payload.</summary>
    public static byte[] Serialize(byte kind, double timestamp, bool isKeyframe, ReadOnlySpan<byte> payload)
    {
        var bytes = new byte[Length + payload.Length];
        new StreamHeader(kind, timestamp, isKeyframe, (uint)payload.Length).Write(bytes);
        payload.CopyTo(bytes.AsSpan(Length));
        return bytes;
    }
}
