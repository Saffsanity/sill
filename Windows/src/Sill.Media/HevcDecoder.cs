using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Sill.Protocol;

namespace Sill.Media;

/// <summary>
/// Media Foundation's HEVC decoder (HEVC Video Extensions' synchronous MFT) as a stream: each
/// access unit in (Annex B: start codes, the parameter sets before a keyframe), NV12 pictures out.
/// Low-latency mode is asked for, so a picture comes out for each access unit as it goes in.
/// One thread at a time; the picture <see cref="Push"/> returns is valid until the next call.
/// </summary>
/// <remarks>
/// COM is called through each interface's vtable by slot number (the order of methods in
/// mfobjects.h and mftransform.h), so nothing needs an interop package. Slots: IUnknown 0–2;
/// IMFAttributes 3–32; IMFMediaType, IMFActivate and IMFSample continue at 33; IMFMediaBuffer and
/// IMFTransform start at 3.
/// </remarks>
[SupportedOSPlatform("windows")]
public sealed unsafe class HevcDecoder : IDisposable
{
    /// <summary>A decoded picture as the decoder stores it: <see cref="Width"/> × <see cref="Height"/>
    /// is the coded size; the SPS's conformance window crops it to what is shown.</summary>
    public sealed record Picture(byte[] Nv12, int Width, int Height, int Stride, int PlaneHeight, bool FullRange, bool Bt601);

    public string Name { get; }
    public HevcSps Sps { get; }

    private IntPtr transform;
    private byte[] nv12 = [];
    private long time;

    /// <param name="sps">The stream's SPS: the coded size goes on the input type (without it HEVC
    /// Video Extensions refuses NV12 output with MF_E_ATTRIBUTENOTFOUND).</param>
    public HevcDecoder(HevcSps sps, Action<string>? log = null)
    {
        Sps = sps;
        Check(CoInitializeEx(IntPtr.Zero, 0 /* COINIT_MULTITHREADED */), "CoInitializeEx", allow: unchecked((int)0x80010106) /* RPC_E_CHANGED_MODE */);
        Check(MFStartup(0x00020070, 0), "MFStartup");
        IntPtr inType = IntPtr.Zero;
        try
        {
            (transform, Name) = CreateDecoder(log);

            // CODECAPI_AVLowLatencyMode: one picture out per access unit in, no reordering wait.
            IntPtr attributes;
            if (((delegate* unmanaged[Stdcall]<IntPtr, IntPtr*, int>)Slot(transform, 8))(transform, &attributes) >= 0 && attributes != IntPtr.Zero)
            {
                Guid lowLatency = CODECAPI_AVLowLatencyMode;
                ((delegate* unmanaged[Stdcall]<IntPtr, Guid*, uint, int>)Slot(attributes, 21))(attributes, &lowLatency, 1);
                Release(attributes);
            }

            Check(MFCreateMediaType(&inType), "MFCreateMediaType");
            SetGuid(inType, MF_MT_MAJOR_TYPE, MFMediaType_Video);
            SetGuid(inType, MF_MT_SUBTYPE, MFVideoFormat_HEVC);
            Guid frameSize = MF_MT_FRAME_SIZE;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, ulong, int>)Slot(inType, 22))(inType, &frameSize,
                ((ulong)sps.CodedWidth << 32) | (uint)sps.CodedHeight), "SetUINT64 (frame size)");
            Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr, uint, int>)Slot(transform, 15))(transform, 0, inType, 0), "SetInputType (HEVC)");
            ChooseNv12(transform);
            Message(0x10000000, "BEGIN_STREAMING");
            Message(0x10000003, "START_OF_STREAM");
        }
        catch
        {
            Dispose();
            throw;
        }
        finally
        {
            if (inType != IntPtr.Zero) Release(inType);
        }
    }

    /// <summary>One access unit in; the newest picture that came out, or null if none did yet.</summary>
    public Picture? Push(byte[] annexB)
    {
        IntPtr sample = MakeSample(annexB, time, cleanPoint: false);
        time += 166_667;   // 1/60 s in 100 ns: the decoder needs increasing times, not real ones
        try
        {
            Picture? latest = null;
            int hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr, uint, int>)Slot(transform, 24))(transform, 0, sample, 0);
            if (hr == MF_E_NOTACCEPTING)
            {
                // Full: take its pictures out, then it takes this one.
                latest = Pull();
                hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr, uint, int>)Slot(transform, 24))(transform, 0, sample, 0);
            }
            Check(hr, "ProcessInput");
            return Pull() ?? latest;
        }
        finally { Release(sample); }
    }

    /// <summary>The end of the stream: whatever pictures the decoder still holds.</summary>
    public Picture? Drain()
    {
        Message(0x10000002, "END_OF_STREAM");
        Message(0x1, "COMMAND_DRAIN");
        return Pull();
    }

    /// <summary>One keyframe (parameter sets included) to one picture, as ticket 05 does it.</summary>
    public static (Picture Picture, string Decoder) DecodeOne(byte[] annexB, HevcSps sps, Action<string>? log = null)
    {
        using var decoder = new HevcDecoder(sps, log);
        var picture = decoder.Push(annexB) ?? decoder.Drain()
            ?? throw new InvalidDataException("The decoder drained without a picture: the input held no decodable keyframe.");
        return (picture, decoder.Name);
    }

    // Every picture ready now; the last is kept (latency beats completeness).
    private Picture? Pull()
    {
        Picture? latest = null;
        for (int changes = 0; changes < 8;)
        {
            var info = default(OutputStreamInfo);
            Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, OutputStreamInfo*, int>)Slot(transform, 7))(transform, 0, &info), "GetOutputStreamInfo");
            bool provides = (info.Flags & 0x300) != 0;   // PROVIDES_SAMPLES or CAN_PROVIDE_SAMPLES
            var buffer = new OutputDataBuffer { StreamId = 0, Sample = provides ? IntPtr.Zero : MakeEmptySample(info.Size) };
            uint status;
            int hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, uint, OutputDataBuffer*, uint*, int>)Slot(transform, 25))(transform, 0, 1, &buffer, &status);
            if (buffer.Events != IntPtr.Zero) Release(buffer.Events);
            if (hr < 0 && buffer.Sample != IntPtr.Zero) { Release(buffer.Sample); buffer.Sample = IntPtr.Zero; }
            if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) return latest;
            if (hr == MF_E_TRANSFORM_STREAM_CHANGE) { ChooseNv12(transform); changes++; continue; }
            Check(hr, "ProcessOutput");
            try { latest = Read(buffer.Sample); }
            finally { Release(buffer.Sample); }
        }
        throw new InvalidOperationException("The decoder kept changing its output type.");
    }

    private void Message(uint message, string what) =>
        Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, nuint, int>)Slot(transform, 23))(transform, message, 0), what);

    // The first synchronous HEVC decoder Media Foundation lists, sorted by merit. Hardware MFTs are
    // asynchronous (an event model left out here), so they are not asked for.
    private static (IntPtr Transform, string Name) CreateDecoder(Action<string>? log)
    {
        var input = new RegisterTypeInfo { Major = MFMediaType_Video, Sub = MFVideoFormat_HEVC };
        IntPtr array; uint count;
        Guid category = MFT_CATEGORY_VIDEO_DECODER;
        Check(MFTEnumEx(category, 0x1 | 0x10 | 0x40 /* SYNCMFT | LOCALMFT | SORTANDFILTER */, &input, IntPtr.Zero, &array, &count), "MFTEnumEx");
        try
        {
            if (count == 0) throw new InvalidOperationException("No HEVC decoder: install HEVC Video Extensions from the Microsoft Store.");
            IntPtr activate = Marshal.ReadIntPtr(array);
            string name = FriendlyName(activate);
            log?.Invoke($"HEVC decoders (synchronous): {count}; using {name}.");
            IntPtr created;
            Guid iid = IID_IMFTransform;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, IntPtr*, int>)Slot(activate, 33))(activate, &iid, &created), "ActivateObject");
            return (created, name);
        }
        finally
        {
            for (int i = 0; i < count; i++) Release(Marshal.ReadIntPtr(array, i * IntPtr.Size));
            Marshal.FreeCoTaskMem(array);
        }
    }

    private static string FriendlyName(IntPtr attributes)
    {
        Guid key = MFT_FRIENDLY_NAME_Attribute;
        char* text; uint length;
        if (((delegate* unmanaged[Stdcall]<IntPtr, Guid*, char**, uint*, int>)Slot(attributes, 13))(attributes, &key, &text, &length) < 0) return "(unnamed)";
        string s = new(text, 0, (int)length);
        Marshal.FreeCoTaskMem((IntPtr)text);
        return s;
    }

    private static void ChooseNv12(IntPtr transform)
    {
        for (uint i = 0; ; i++)
        {
            IntPtr type;
            int hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, uint, IntPtr*, int>)Slot(transform, 14))(transform, 0, i, &type);
            if (hr == MF_E_NO_MORE_TYPES) throw new InvalidOperationException("The decoder offers no NV12 output.");
            Check(hr, "GetOutputAvailableType");
            try
            {
                if (GetGuid(type, MF_MT_SUBTYPE) != MFVideoFormat_NV12) continue;
                Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr, uint, int>)Slot(transform, 16))(transform, 0, type, 0), "SetOutputType (NV12)");
                return;
            }
            finally { Release(type); }
        }
    }

    private Picture Read(IntPtr sample)
    {
        IntPtr type;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr*, int>)Slot(transform, 18))(transform, 0, &type), "GetOutputCurrentType");
        int width, height, stride; bool fullRange, bt601;
        try
        {
            ulong size = GetUInt64(type, MF_MT_FRAME_SIZE) ?? throw new InvalidDataException("The output type has no frame size.");
            width = (int)(size >> 32); height = (int)(size & 0xFFFFFFFF);
            stride = (int?)GetUInt32(type, MF_MT_DEFAULT_STRIDE) is { } s && s > 0 ? s : width;
            fullRange = GetUInt32(type, MF_MT_VIDEO_NOMINAL_RANGE) == 1;   // MFNominalRange_0_255
            bt601 = GetUInt32(type, MF_MT_YUV_MATRIX) == 2;                // MFVideoTransferMatrix_BT601
        }
        finally { Release(type); }

        IntPtr buffer;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr*, int>)Slot(sample, 41))(sample, &buffer), "ConvertToContiguousBuffer");
        try
        {
            byte* data; uint max, length;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, byte**, uint*, uint*, int>)Slot(buffer, 3))(buffer, &data, &max, &length), "Lock");
            try
            {
                // One buffer, reused for every picture: 12 MB at 4K would churn the GC at 60 a second.
                if (nv12.Length != length) nv12 = new byte[length];
                new ReadOnlySpan<byte>(data, (int)length).CopyTo(nv12);
                // The Y plane may be padded below the picture: the buffer is Y (stride × rows) then
                // UV (stride × rows / 2).
                int planeHeight = Math.Max(height, (int)(length * 2 / 3 / (uint)stride));
                return new Picture(nv12, width, height, stride, planeHeight, fullRange, bt601);
            }
            finally { ((delegate* unmanaged[Stdcall]<IntPtr, int>)Slot(buffer, 4))(buffer); }
        }
        finally { Release(buffer); }
    }

    private static IntPtr MakeSample(byte[] data, long time, bool cleanPoint)
    {
        IntPtr sample = MakeEmptySample((uint)data.Length);
        IntPtr buffer;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr*, int>)Slot(sample, 40))(sample, 0, &buffer), "GetBufferByIndex");
        try
        {
            byte* p; uint max, cur;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, byte**, uint*, uint*, int>)Slot(buffer, 3))(buffer, &p, &max, &cur), "Lock");
            data.CopyTo(new Span<byte>(p, data.Length));
            ((delegate* unmanaged[Stdcall]<IntPtr, int>)Slot(buffer, 4))(buffer);
            Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, int>)Slot(buffer, 6))(buffer, (uint)data.Length), "SetCurrentLength");
        }
        finally { Release(buffer); }
        Check(((delegate* unmanaged[Stdcall]<IntPtr, long, int>)Slot(sample, 36))(sample, time), "SetSampleTime");
        Check(((delegate* unmanaged[Stdcall]<IntPtr, long, int>)Slot(sample, 38))(sample, 166_667), "SetSampleDuration");
        if (cleanPoint)
        {
            Guid clean = MFSampleExtension_CleanPoint;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, uint, int>)Slot(sample, 21))(sample, &clean, 1), "CleanPoint");
        }
        return sample;
    }

    private static IntPtr MakeEmptySample(uint size)
    {
        IntPtr sample, buffer;
        Check(MFCreateSample(&sample), "MFCreateSample");
        Check(MFCreateMemoryBuffer(Math.Max(size, 1), &buffer), "MFCreateMemoryBuffer");
        try { Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, int>)Slot(sample, 42))(sample, buffer), "AddBuffer"); }
        finally { Release(buffer); }
        return sample;
    }

    public void Dispose()
    {
        if (transform != IntPtr.Zero) { Release(transform); transform = IntPtr.Zero; MFShutdown(); }
    }

    // ---- attributes (IMFAttributes slots) ----

    private static void SetGuid(IntPtr attributes, Guid key, Guid value) =>
        Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, Guid*, int>)Slot(attributes, 24))(attributes, &key, &value), "SetGUID");

    private static Guid GetGuid(IntPtr attributes, Guid key)
    {
        Guid value;
        return ((delegate* unmanaged[Stdcall]<IntPtr, Guid*, Guid*, int>)Slot(attributes, 10))(attributes, &key, &value) < 0 ? Guid.Empty : value;
    }

    private static uint? GetUInt32(IntPtr attributes, Guid key)
    {
        uint value;
        return ((delegate* unmanaged[Stdcall]<IntPtr, Guid*, uint*, int>)Slot(attributes, 7))(attributes, &key, &value) < 0 ? null : value;
    }

    private static ulong? GetUInt64(IntPtr attributes, Guid key)
    {
        ulong value;
        return ((delegate* unmanaged[Stdcall]<IntPtr, Guid*, ulong*, int>)Slot(attributes, 8))(attributes, &key, &value) < 0 ? null : value;
    }

    // ---- COM plumbing ----

    private static void* Slot(IntPtr obj, int slot) => (*(void***)obj)[slot];
    private static void Release(IntPtr obj) => ((delegate* unmanaged[Stdcall]<IntPtr, uint>)Slot(obj, 2))(obj);

    private static void Check(int hr, string what, int? allow = null)
    {
        if (hr < 0 && hr != allow) throw new COMException($"{what} failed (0x{hr:X8})", hr);
    }

    [StructLayout(LayoutKind.Sequential)] private struct RegisterTypeInfo { public Guid Major; public Guid Sub; }
    [StructLayout(LayoutKind.Sequential)] private struct OutputStreamInfo { public uint Flags; public uint Size; public uint Alignment; }
    [StructLayout(LayoutKind.Sequential)] private struct OutputDataBuffer { public uint StreamId; public IntPtr Sample; public uint Status; public IntPtr Events; }

    private const int MF_E_TRANSFORM_NEED_MORE_INPUT = unchecked((int)0xC00D6D72);
    private const int MF_E_TRANSFORM_STREAM_CHANGE = unchecked((int)0xC00D6D61);
    private const int MF_E_NO_MORE_TYPES = unchecked((int)0xC00D36B9);
    private const int MF_E_NOTACCEPTING = unchecked((int)0xC00D36B5);

    private static readonly Guid MFT_CATEGORY_VIDEO_DECODER = new("d6c02d4b-6833-45b4-971a-05a4b04bab91");
    private static readonly Guid MFMediaType_Video = new("73646976-0000-0010-8000-00aa00389b71");
    private static readonly Guid MFVideoFormat_HEVC = new("43564548-0000-0010-8000-00aa00389b71");
    private static readonly Guid MFVideoFormat_NV12 = new("3231564e-0000-0010-8000-00aa00389b71");
    private static readonly Guid MF_MT_MAJOR_TYPE = new("48eba18e-f8c9-4687-bf11-0a74c9f96a8f");
    private static readonly Guid MF_MT_SUBTYPE = new("f7e34c9a-42e8-4714-b74b-cb29d72c35e5");
    private static readonly Guid MF_MT_FRAME_SIZE = new("1652c33d-d6b2-4012-b834-72030849a37d");
    private static readonly Guid MF_MT_DEFAULT_STRIDE = new("644b4e48-1e02-4516-b0eb-c01ca9d49ac6");
    private static readonly Guid MF_MT_VIDEO_NOMINAL_RANGE = new("c21b8ee5-b956-4071-8daf-325edf5cab11");
    private static readonly Guid MF_MT_YUV_MATRIX = new("3e23d450-2c75-4d25-a00e-b91670d12327");
    private static readonly Guid MFSampleExtension_CleanPoint = new("9cdf01d8-a0f0-43ba-b077-eaa06cbd728a");
    private static readonly Guid MFT_FRIENDLY_NAME_Attribute = new("314ffbae-5b41-4c95-9c19-4e7d586face3");
    private static readonly Guid CODECAPI_AVLowLatencyMode = new("9c27891a-ed7a-40e1-88e8-b22727a024ee");
    private static readonly Guid IID_IMFTransform = new("bf94c121-5b05-4e6f-8000-ba598961414d");

    [DllImport("ole32.dll")] private static extern int CoInitializeEx(IntPtr reserved, uint coInit);
    [DllImport("mfplat.dll")] private static extern int MFStartup(uint version, uint flags);
    [DllImport("mfplat.dll")] private static extern int MFShutdown();
    [DllImport("mfplat.dll")] private static extern int MFCreateMediaType(IntPtr* type);
    [DllImport("mfplat.dll")] private static extern int MFCreateSample(IntPtr* sample);
    [DllImport("mfplat.dll")] private static extern int MFCreateMemoryBuffer(uint maxLength, IntPtr* buffer);
    [DllImport("mfplat.dll")]
    private static extern int MFTEnumEx(Guid category, uint flags, RegisterTypeInfo* input, IntPtr output, IntPtr* activates, uint* count);
}
