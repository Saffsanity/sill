using System.Runtime.InteropServices;
using System.Runtime.Versioning;

/// <summary>
/// Ticket 05: one HEVC access unit through Media Foundation's HEVC decoder (HEVC Video
/// Extensions), one NV12 picture out. A synchronous decoder MFT, fed Annex B (the parameter
/// sets, then the access unit's NAL units, each after a start code), drained, and read once.
/// </summary>
/// <remarks>
/// COM is called through each interface's vtable by slot number (the order of methods in
/// mfobjects.h and mftransform.h), so the spike needs no interop package. Slots: IUnknown 0–2;
/// IMFAttributes 3–32; IMFMediaType, IMFActivate and IMFSample continue at 33; IMFMediaBuffer and
/// IMFTransform start at 3.
/// </remarks>
[SupportedOSPlatform("windows")]
static unsafe class HevcDecoder
{
    /// <summary>The decoded picture as stored (<paramref name="Width"/> × <paramref name="Height"/>,
    /// the coded size the decoder reports).</summary>
    public sealed record Picture(byte[] Nv12, int Width, int Height, int Stride, int PlaneHeight, bool FullRange, bool Bt601, string Decoder);

    /// <summary>Decodes <paramref name="annexB"/>, which must hold the parameter sets and one
    /// keyframe; <paramref name="sps"/> gives the coded size the input type needs (without it
    /// the HEVC Video Extensions decoder refuses NV12 output: MF_E_ATTRIBUTENOTFOUND). Throws with
    /// the failing call's HRESULT.</summary>
    public static Picture Decode(byte[] annexB, Sill.Protocol.HevcSps sps, Action<string> log)
    {
        Check(CoInitializeEx(IntPtr.Zero, 0 /* COINIT_MULTITHREADED */), "CoInitializeEx", allow: unchecked((int)0x80010106) /* RPC_E_CHANGED_MODE */);
        Check(MFStartup(0x00020070, 0), "MFStartup");
        IntPtr transform = IntPtr.Zero, inType = IntPtr.Zero;
        try
        {
            (transform, string name) = CreateDecoder(log);

            Check(MFCreateMediaType(&inType), "MFCreateMediaType");
            SetGuid(inType, MF_MT_MAJOR_TYPE, MFMediaType_Video);
            SetGuid(inType, MF_MT_SUBTYPE, MFVideoFormat_HEVC);
            Guid frameSize = MF_MT_FRAME_SIZE;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, ulong, int>)Slot(inType, 22))(inType, &frameSize,
                ((ulong)sps.CodedWidth << 32) | (uint)sps.CodedHeight), "SetUINT64 (frame size)");
            Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr, uint, int>)Slot(transform, 15))(transform, 0, inType, 0), "SetInputType (HEVC)");
            ChooseNv12(transform, log);

            Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, nuint, int>)Slot(transform, 23))(transform, 0x10000000, 0), "BEGIN_STREAMING");
            Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, nuint, int>)Slot(transform, 23))(transform, 0x10000003, 0), "START_OF_STREAM");

            IntPtr sample = MakeSample(annexB);
            try
            {
                int hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr, uint, int>)Slot(transform, 24))(transform, 0, sample, 0);
                Check(hr, "ProcessInput");
            }
            finally { Release(sample); }
            Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, nuint, int>)Slot(transform, 23))(transform, 0x10000002, 0), "END_OF_STREAM");
            Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, nuint, int>)Slot(transform, 23))(transform, 0x1 /* COMMAND_DRAIN */, 0), "COMMAND_DRAIN");

            for (int attempt = 0; attempt < 8; attempt++)
            {
                var info = default(OutputStreamInfo);
                Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, OutputStreamInfo*, int>)Slot(transform, 7))(transform, 0, &info), "GetOutputStreamInfo");
                bool provides = (info.Flags & 0x300) != 0;   // PROVIDES_SAMPLES or CAN_PROVIDE_SAMPLES
                var buffer = new OutputDataBuffer { StreamId = 0, Sample = provides ? IntPtr.Zero : MakeEmptySample(info.Size) };
                uint status;
                int hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, uint, OutputDataBuffer*, uint*, int>)Slot(transform, 25))(transform, 0, 1, &buffer, &status);
                if (buffer.Events != IntPtr.Zero) Release(buffer.Events);
                if (hr == MF_E_TRANSFORM_STREAM_CHANGE)
                {
                    log("The decoder changed its output type (the stream's size is now known): choosing NV12 again.");
                    if (buffer.Sample != IntPtr.Zero) Release(buffer.Sample);
                    ChooseNv12(transform, log);
                    continue;
                }
                if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT)
                {
                    if (buffer.Sample != IntPtr.Zero) Release(buffer.Sample);
                    throw new InvalidDataException("The decoder drained without a picture: the input held no decodable keyframe.");
                }
                Check(hr, "ProcessOutput");
                try { return Read(transform, buffer.Sample, name); }
                finally { Release(buffer.Sample); }
            }
            throw new InvalidOperationException("The decoder kept changing its output type.");
        }
        finally
        {
            if (inType != IntPtr.Zero) Release(inType);
            if (transform != IntPtr.Zero) Release(transform);
            MFShutdown();
        }
    }

    // The first synchronous HEVC decoder Media Foundation lists, sorted by merit. Hardware MFTs are
    // asynchronous (an event model the spike leaves out), so they are not asked for here.
    private static (IntPtr Transform, string Name) CreateDecoder(Action<string> log)
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
            log($"HEVC decoders (synchronous): {count}; using {name}.");
            IntPtr transform;
            Guid iid = IID_IMFTransform;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, IntPtr*, int>)Slot(activate, 33))(activate, &iid, &transform), "ActivateObject");
            return (transform, name);
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

    private static void ChooseNv12(IntPtr transform, Action<string> log)
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

    private static Picture Read(IntPtr transform, IntPtr sample, string name)
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
                var nv12 = new ReadOnlySpan<byte>(data, (int)length).ToArray();
                // The Y plane may be padded below the picture (to a multiple of 16 rows): the
                // buffer is Y (stride × rows) then UV (stride × rows / 2).
                int planeHeight = Math.Max(height, (int)(length * 2 / 3 / (uint)stride));
                return new Picture(nv12, width, height, stride, planeHeight, fullRange, bt601, name);
            }
            finally { ((delegate* unmanaged[Stdcall]<IntPtr, int>)Slot(buffer, 4))(buffer); }
        }
        finally { Release(buffer); }
    }

    private static IntPtr MakeSample(byte[] data)
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
        Check(((delegate* unmanaged[Stdcall]<IntPtr, long, int>)Slot(sample, 36))(sample, 0), "SetSampleTime");
        Check(((delegate* unmanaged[Stdcall]<IntPtr, long, int>)Slot(sample, 38))(sample, 166_667), "SetSampleDuration");   // 1/60 s in 100 ns
        Guid clean = MFSampleExtension_CleanPoint;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, uint, int>)Slot(sample, 21))(sample, &clean, 1), "CleanPoint");
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
