using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using static Sill.Media.Com;

namespace Sill.Media;

/// <summary>
/// A Direct3D 11 device with video support, shared by the HEVC decoder (through an
/// <c>IMFDXGIDeviceManager</c>, so it decodes on the GPU) and <see cref="VideoRenderer"/> (which
/// draws its NV12 textures). Multithread protection is on, as Media Foundation requires.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed unsafe class GpuDevice : IDisposable
{
    /// <summary>The adapter's name, as Windows gives it ("NVIDIA GeForce RTX 3050 Laptop GPU").</summary>
    public string AdapterName { get; }

    internal IntPtr Device { get; private set; }
    internal IntPtr Context { get; private set; }
    internal IntPtr Manager { get; private set; }
    internal IntPtr Factory { get; private set; }   // IDXGIFactory2, for swap chains

    /// <param name="adapter">An index into DXGI's adapters (0 is the one driving the main display),
    /// or null for Windows' default.</param>
    public GpuDevice(int? adapter = null)
    {
        try
        {
            IntPtr chosen = IntPtr.Zero;
            if (adapter is { } index)
            {
                IntPtr factory1;
                Guid iid = IID_IDXGIFactory1;
                Check(CreateDXGIFactory1(&iid, &factory1), "CreateDXGIFactory1");
                try
                {
                    IntPtr a;
                    Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr*, int>)Slot(factory1, 12))(factory1, (uint)index, &a),
                        $"EnumAdapters1 ({index})");
                    chosen = a;
                }
                finally { Release(factory1); }
            }

            IntPtr device, context;
            int level;
            int* levels = stackalloc int[] { 0xb100, 0xb000 };   // 11.1, 11.0
            const uint Flags = 0x20 | 0x800;                      // BGRA_SUPPORT | VIDEO_SUPPORT
            int hr = D3D11CreateDevice(chosen, chosen == IntPtr.Zero ? 1 /* HARDWARE */ : 0 /* UNKNOWN */, IntPtr.Zero,
                Flags, levels, 2, 7, &device, &level, &context);
            Release(chosen);
            Check(hr, "D3D11CreateDevice");
            Device = device; Context = context;

            IntPtr multithread = Query(Device, IID_ID3D10Multithread);
            ((delegate* unmanaged[Stdcall]<IntPtr, int, int>)Slot(multithread, 5))(multithread, 1);   // SetMultithreadProtected
            Release(multithread);

            // The device's adapter: its name, and the factory that made it (a swap chain must come from it).
            IntPtr dxgiDevice = Query(Device, IID_IDXGIDevice), dxgiAdapter, factory;
            try
            {
                Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr*, int>)Slot(dxgiDevice, 7))(dxgiDevice, &dxgiAdapter), "GetAdapter");
            }
            finally { Release(dxgiDevice); }
            try
            {
                byte* desc = stackalloc byte[512];   // DXGI_ADAPTER_DESC: WCHAR Description[128] first
                Check(((delegate* unmanaged[Stdcall]<IntPtr, byte*, int>)Slot(dxgiAdapter, 8))(dxgiAdapter, desc), "GetDesc");
                AdapterName = new string((char*)desc).Trim();
                Guid iid = IID_IDXGIFactory2;
                Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, IntPtr*, int>)Slot(dxgiAdapter, 6))(dxgiAdapter, &iid, &factory), "GetParent (factory)");
                Factory = factory;
            }
            finally { Release(dxgiAdapter); }

            uint token; IntPtr manager;
            Check(MFCreateDXGIDeviceManager(&token, &manager), "MFCreateDXGIDeviceManager");
            Manager = manager;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, int>)Slot(Manager, 7))(Manager, Device, token), "ResetDevice");
        }
        catch
        {
            Dispose();
            throw;
        }
        AdapterName ??= "GPU";
    }

    /// <summary>Waits until the GPU has finished everything asked of it so far (an event query), so
    /// a measurement of decode time counts the decode, not just its submission.</summary>
    public void WaitForIdle()
    {
        IntPtr query;
        uint* desc = stackalloc uint[] { 0 /* D3D11_QUERY_EVENT */, 0 };
        Check(((delegate* unmanaged[Stdcall]<IntPtr, uint*, IntPtr*, int>)Slot(Device, 24))(Device, desc, &query), "CreateQuery");
        try
        {
            ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, void>)Slot(Context, 28))(Context, query);   // End
            int done;
            int hr;
            while ((hr = ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, int*, uint, uint, int>)Slot(Context, 29))(Context, query, &done, 4, 0)) == 1)
                Thread.SpinWait(50);
            Check(hr, "GetData (event query)");
        }
        finally { Release(query); }
    }

    /// <summary>Copies a GPU picture back to the CPU (a staging texture): for checks against the
    /// software decoder, never on the drawing path.</summary>
    public HevcDecoder.Picture ReadBack(GpuPicture picture)
    {
        // D3D11_TEXTURE2D_DESC: the picture's size, 1 mip, 1 slice, NV12, 1 sample, staging, no
        // binding, CPU read.
        uint* desc = stackalloc uint[] { (uint)picture.Width, (uint)picture.Height, 1, 1, 103, 1, 0, 3, 0, 0x20000, 0 };
        IntPtr staging;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, uint*, IntPtr, IntPtr*, int>)Slot(Device, 5))(Device, desc, IntPtr.Zero, &staging), "CreateTexture2D (staging)");
        try
        {
            ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, uint, uint, uint, IntPtr, uint, IntPtr, void>)Slot(Context, 46))(
                Context, staging, 0, 0, 0, 0, picture.Texture, picture.Slice, IntPtr.Zero);   // CopySubresourceRegion
            Mapped mapped;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, uint, uint, Mapped*, int>)Slot(Context, 14))(Context, staging, 0, 1 /* READ */, 0, &mapped), "Map");
            try
            {
                int stride = (int)mapped.RowPitch, rows = picture.Height + picture.Height / 2;
                var nv12 = new byte[stride * rows];
                // The UV plane follows the Y plane's rows in a mapped NV12 texture.
                new ReadOnlySpan<byte>((void*)mapped.Data, nv12.Length).CopyTo(nv12);
                return new HevcDecoder.Picture(nv12, picture.Width, picture.Height, stride, picture.Height, picture.FullRange, picture.Bt601);
            }
            finally { ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, void>)Slot(Context, 15))(Context, staging, 0); }
        }
        finally { Release(staging); }
    }

    [StructLayout(LayoutKind.Sequential)] private struct Mapped { public IntPtr Data; public uint RowPitch, DepthPitch; }

    public void Dispose()
    {
        Release(Manager); Manager = IntPtr.Zero;
        Release(Factory); Factory = IntPtr.Zero;
        Release(Context); Context = IntPtr.Zero;
        Release(Device); Device = IntPtr.Zero;
    }

    private static readonly Guid IID_IDXGIFactory1 = new("770aae78-f26f-4dba-a829-253c83d1b387");
    private static readonly Guid IID_IDXGIFactory2 = new("50c83a1c-e072-4c48-87b0-3630fa36a6d0");
    private static readonly Guid IID_IDXGIDevice = new("54ec77fa-1377-44e6-8c32-88fd5f44c84c");
    private static readonly Guid IID_ID3D10Multithread = new("9b7e4e00-342c-4106-a19f-4f2704f689f0");

    [DllImport("d3d11.dll")]
    private static extern int D3D11CreateDevice(IntPtr adapter, int driverType, IntPtr software, uint flags, int* levels, uint count,
        uint sdkVersion, IntPtr* device, int* level, IntPtr* context);
    [DllImport("dxgi.dll")] private static extern int CreateDXGIFactory1(Guid* iid, IntPtr* factory);
    [DllImport("mfplat.dll")] private static extern int MFCreateDXGIDeviceManager(uint* resetToken, IntPtr* manager);
}
