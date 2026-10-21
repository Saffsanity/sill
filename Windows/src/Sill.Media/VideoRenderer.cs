using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using static Sill.Media.Com;

namespace Sill.Media;

/// <summary>
/// A picture the GPU decoded: a slice of the decoder's NV12 texture array, kept alive by its
/// Media Foundation sample until disposed. <see cref="Width"/> × <see cref="Height"/> is the coded
/// size; the SPS's conformance window crops it to what is shown.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class GpuPicture : IDisposable
{
    internal IntPtr Sample, Texture;
    internal uint Slice;
    public uint ArraySlice => Slice;
    public int Width { get; }
    public int Height { get; }
    public bool FullRange { get; }
    public bool Bt601 { get; }

    internal GpuPicture(IntPtr sample, IntPtr texture, uint slice, int width, int height, bool fullRange, bool bt601)
    {
        Sample = sample; Texture = texture; Slice = slice; Width = width; Height = height; FullRange = fullRange; Bt601 = bt601;
    }

    public void Dispose()
    {
        Release(Texture); Texture = IntPtr.Zero;
        Release(Sample); Sample = IntPtr.Zero;
    }
}

/// <summary>
/// Draws <see cref="GpuPicture"/>s into a window with Direct3D 11: a flip-model swap chain on the
/// window, and the video processor (the GPU's own NV12 to RGB, scaling and colour matrix) from the
/// decoder's texture straight to the back buffer, letterboxed on black. Nothing comes back to the
/// CPU. One thread at a time.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed unsafe class VideoRenderer : IDisposable
{
    private readonly GpuDevice gpu;
    private readonly IntPtr hwnd;
    private IntPtr swapChain, videoDevice, videoContext;
    private IntPtr enumerator, processor;
    private int inWidth, inHeight;
    private int width, height;
    private readonly Dictionary<(IntPtr, uint), IntPtr> inputViews = [];
    private readonly Dictionary<IntPtr, IntPtr> outputViews = [];

    /// <summary>The colour around a letterboxed picture.</summary>
    public System.Drawing.Color Background { get; set; } = System.Drawing.Color.Black;

    public VideoRenderer(GpuDevice gpu, IntPtr hwnd, int width, int height)
    {
        this.gpu = gpu; this.hwnd = hwnd;
        this.width = Math.Max(1, width); this.height = Math.Max(1, height);
        try
        {
            videoDevice = Query(gpu.Device, IID_ID3D11VideoDevice);
            videoContext = Query(gpu.Context, IID_ID3D11VideoContext);
            // DXGI_SWAP_CHAIN_DESC1: width, height, B8G8R8A8, no stereo, 1 sample, render target
            // output, 2 buffers, stretch, flip-discard, alpha unspecified, no flags.
            uint* desc = stackalloc uint[] { (uint)this.width, (uint)this.height, 87, 0, 1, 0, 0x20, 2, 0, 4, 0, 0 };
            IntPtr chain;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, IntPtr, uint*, IntPtr, IntPtr, IntPtr*, int>)Slot(gpu.Factory, 15))(
                gpu.Factory, gpu.Device, hwnd, desc, IntPtr.Zero, IntPtr.Zero, &chain), "CreateSwapChainForHwnd");
            swapChain = chain;
            // Alt+Enter is the Mac's (⌥Return), never DXGI's full screen.
            ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, int>)Slot(gpu.Factory, 8))(gpu.Factory, hwnd, 0x2 /* NO_ALT_ENTER */);
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    /// <summary>The window's new size in pixels; the buffers follow before the next draw.</summary>
    public void Resize(int newWidth, int newHeight)
    {
        newWidth = Math.Max(1, newWidth); newHeight = Math.Max(1, newHeight);
        if (newWidth == width && newHeight == height) return;
        foreach (var view in outputViews.Values) Release(view);
        outputViews.Clear();
        Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, uint, uint, uint, uint, int>)Slot(swapChain, 13))(swapChain, 0,
            (uint)newWidth, (uint)newHeight, 0 /* keep the format */, 0), "ResizeBuffers");
        width = newWidth; height = newHeight;
    }

    /// <summary>Draws the picture's shown part (<paramref name="crop"/>, in coded pixels) and presents.</summary>
    public void Draw(GpuPicture picture, (int Left, int Top, int Width, int Height) crop)
    {
        IntPtr texture = picture.Texture;
        // D3D11_TEXTURE2D_DESC: Width, Height first. The decoder's textures can be taller than the
        // coded size (aligned); the processor is made for the texture.
        uint* tdesc = stackalloc uint[11];
        ((delegate* unmanaged[Stdcall]<IntPtr, uint*, void>)Slot(texture, 10))(texture, tdesc);
        if (processor == IntPtr.Zero || inWidth != (int)tdesc[0] || inHeight != (int)tdesc[1]) MakeProcessor((int)tdesc[0], (int)tdesc[1]);

        IntPtr input = InputView(texture, picture.Slice);
        IntPtr backBuffer;
        Guid iid = IID_ID3D11Texture2D;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, Guid*, IntPtr*, int>)Slot(swapChain, 9))(swapChain, 0, &iid, &backBuffer), "GetBuffer");
        IntPtr output;
        try { output = OutputView(backBuffer); }
        finally { Release(backBuffer); }

        var c = videoContext;
        var p = processor;
        // The stream: BT.709 or 601, full or video range, as the decoder's output type says.
        uint streamSpace = (picture.Bt601 ? 0u : 1u) << 2 | (picture.FullRange ? 2u : 1u) << 4;
        uint outputSpace = 0;   // RGB, full range
        ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, uint*, void>)Slot(c, 28))(c, p, 0, &streamSpace);
        ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint*, void>)Slot(c, 15))(c, p, &outputSpace);

        var (x, y, w, h) = Sill.Protocol.Letterbox.Fit(crop.Width, crop.Height, width, height);
        Rect source = new(crop.Left, crop.Top, crop.Left + crop.Width, crop.Top + crop.Height);
        Rect dest = new(x, y, x + w, y + h);
        Rect target = new(0, 0, width, height);
        float* black = stackalloc float[] { Background.R / 255f, Background.G / 255f, Background.B / 255f, 1 };
        ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, int, Rect*, void>)Slot(c, 13))(c, p, 1, &target);     // SetOutputTargetRect
        ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, int, float*, void>)Slot(c, 14))(c, p, 0, black);      // SetOutputBackgroundColor (RGB)
        ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, int, Rect*, void>)Slot(c, 30))(c, p, 0, 1, &source);   // SetStreamSourceRect
        ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, int, Rect*, void>)Slot(c, 31))(c, p, 0, 1, &dest);     // SetStreamDestRect

        var stream = new ProcessorStream { Enable = 1, InputSurface = input };
        Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, IntPtr, uint, uint, ProcessorStream*, int>)Slot(c, 53))(c, p, output, 0, 1, &stream),
            "VideoProcessorBlt");
        // Sync interval 0: never wait for the display here; with flip-discard the compositor shows
        // the newest picture at each refresh.
        int hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, uint, int>)Slot(swapChain, 8))(swapChain, 0, 0);
        Check(hr, "Present", allow: 0x087A0001 /* DXGI_STATUS_OCCLUDED */);
    }

    private void MakeProcessor(int textureWidth, int textureHeight)
    {
        ReleaseProcessor();
        // D3D11_VIDEO_PROCESSOR_CONTENT_DESC: progressive, 60/1 in, size in, 60/1 out, size out, optimal speed.
        uint* desc = stackalloc uint[] { 0, 60, 1, (uint)textureWidth, (uint)textureHeight, 60, 1, (uint)textureWidth, (uint)textureHeight, 1 };
        IntPtr e, proc;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, uint*, IntPtr*, int>)Slot(videoDevice, 10))(videoDevice, desc, &e), "CreateVideoProcessorEnumerator");
        enumerator = e;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, IntPtr*, int>)Slot(videoDevice, 4))(videoDevice, enumerator, 0, &proc), "CreateVideoProcessor");
        processor = proc;
        inWidth = textureWidth; inHeight = textureHeight;
        // Progressive frames, and no driver "enhancement" (sharpening, noise reduction) of the Mac's pixels.
        ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, uint, void>)Slot(videoContext, 27))(videoContext, processor, 0, 0);
        ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, int, void>)Slot(videoContext, 37))(videoContext, processor, 0, 0);
    }

    private IntPtr InputView(IntPtr texture, uint slice)
    {
        if (inputViews.TryGetValue((texture, slice), out var view)) return view;
        if (inputViews.Count >= 64) ClearInputViews();   // a new decoder's textures: the old views go
        uint* desc = stackalloc uint[] { 0 /* FourCC */, 1 /* TEXTURE2D */, 0 /* mip */, slice };
        Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, IntPtr, uint*, IntPtr*, int>)Slot(videoDevice, 8))(videoDevice, texture, enumerator, desc, &view),
            "CreateVideoProcessorInputView");
        inputViews[(texture, slice)] = view;
        return view;
    }

    private IntPtr OutputView(IntPtr backBuffer)
    {
        if (outputViews.TryGetValue(backBuffer, out var view)) return view;
        uint* desc = stackalloc uint[] { 1 /* TEXTURE2D */, 0, 0, 0 };
        Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, IntPtr, uint*, IntPtr*, int>)Slot(videoDevice, 9))(videoDevice, backBuffer, enumerator, desc, &view),
            "CreateVideoProcessorOutputView");
        outputViews[backBuffer] = view;
        return view;
    }

    /// <summary>Forgets the views of a decoder that is going away (its textures with it).</summary>
    public void ClearInputViews()
    {
        foreach (var view in inputViews.Values) Release(view);
        inputViews.Clear();
    }

    private void ReleaseProcessor()
    {
        ClearInputViews();
        foreach (var view in outputViews.Values) Release(view);
        outputViews.Clear();
        Release(processor); processor = IntPtr.Zero;
        Release(enumerator); enumerator = IntPtr.Zero;
    }

    public void Dispose()
    {
        ReleaseProcessor();
        Release(swapChain); swapChain = IntPtr.Zero;
        Release(videoContext); videoContext = IntPtr.Zero;
        Release(videoDevice); videoDevice = IntPtr.Zero;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly record struct Rect(int Left, int Top, int Right, int Bottom);

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessorStream
    {
        public int Enable; public uint OutputIndex, InputFrameOrField, PastFrames, FutureFrames;
        public IntPtr PastSurfaces, InputSurface, FutureSurfaces, PastSurfacesRight, InputSurfaceRight, FutureSurfacesRight;
    }

    private static readonly Guid IID_ID3D11VideoDevice = new("10ec4d5b-975a-4689-b9e4-d0aac30fe333");
    private static readonly Guid IID_ID3D11VideoContext = new("61f21c45-3c0e-4a74-9cea-67100d9ad5e4");
    internal static readonly Guid IID_ID3D11Texture2D = new("6f15aaf2-d208-4e89-9ab4-489535d34f9c");
}
