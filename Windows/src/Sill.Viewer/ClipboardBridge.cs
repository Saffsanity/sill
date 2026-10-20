using System.Diagnostics;
using System.Runtime.InteropServices;
using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The clipboard both ways (kind 32, ticket 09), on the UI thread. The Mac's text is written to
/// Windows' clipboard as it arrives. Windows' text goes to the Mac when it changes while the viewer
/// is in front, and when the viewer comes to the front after a copy made elsewhere (Windows asks
/// nobody before an app reads the clipboard, so no chip as on the iPad: coming back to Sill is the
/// consent). Never a copy its app marks as private (<see cref="ClipboardPolicy.PcDecides"/>: the
/// formats are looked at before the text is read), never this viewer's own write, never what was on
/// the clipboard when the viewer started or the switch went on. The rules are ClipboardPolicy's;
/// this does the reading, writing and timing. Logs sizes and decisions, never contents.
/// </summary>
sealed class ClipboardBridge : NativeWindow, IDisposable
{
    private const int WM_CLIPBOARDUPDATE = 0x031D, CF_UNICODETEXT = 13;
    private static readonly IntPtr HWND_MESSAGE = new(-3);
    private static readonly uint ExcludeFormat = RegisterClipboardFormat(ClipboardPolicy.ExcludeFormat),
        HistoryFormat = RegisterClipboardFormat(ClipboardPolicy.HistoryFormat),
        CloudFormat = RegisterClipboardFormat(ClipboardPolicy.CloudFormat);

    private readonly Func<bool> inFront;
    private readonly Action<byte[]> send;
    private readonly Action<string> log;
    private readonly ClipboardOutbox outbox = new();
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly System.Windows.Forms.Timer later = new();
    private int? hostClipboard;
    private bool shareOn, subscribed;
    private uint handled, ownSequence;   // the copy last dealt with; this viewer's last write
    private ClipboardPolicy.Sent? lastSent;

    public ClipboardBridge(bool shareOn, Func<bool> inFront, Action<byte[]> send, Action<string> log)
    {
        this.shareOn = shareOn; this.inFront = inFront; this.send = send; this.log = log;
        CreateHandle(new CreateParams { Parent = HWND_MESSAGE });
        if (!AddClipboardFormatListener(Handle)) log($"Clipboard: no listener (error {Marshal.GetLastWin32Error()}); this PC's copies stay here.");
        handled = GetClipboardSequenceNumber();   // what is there already is never sent
        later.Tick += (_, _) => { later.Stop(); Flush(); };
    }

    /// <summary>The switch, Settings › This PC's Share Clipboard.</summary>
    public bool ShareOn
    {
        get => shareOn;
        set
        {
            if (value == shareOn) return;
            shareOn = value;
            if (value) handled = GetClipboardSequenceNumber();   // copies made while it was off stay here
            Step(value ? "switched on" : "switched off");
        }
    }

    /// <summary>Whether the Mac says it shares its clipboard; null before its first window list.</summary>
    public bool? MacShares => seenList ? ClipboardPolicy.HostTakes(hostClipboard) : null;
    private bool seenList;

    /// <summary>A new connection: nothing subscribed on it yet, nothing held for the old one.</summary>
    public void SessionChanged()
    {
        hostClipboard = null; seenList = false; subscribed = false;
        outbox.Reset(); later.Stop();
    }

    /// <summary>A window list's <c>clipboard</c>; true when whether the Mac shares it changed.</summary>
    public bool HostSays(int? clipboard)
    {
        bool before = MacShares == true;
        hostClipboard = clipboard; seenList = true;
        Step("the Mac shares its clipboard");
        return before != (MacShares == true);
    }

    /// <summary>Subscribe or stop as the switch and the Mac's list say; a new subscription looks at
    /// once if a copy was made here meanwhile and the viewer is in front.</summary>
    private void Step(string why)
    {
        var (step, now) = ClipboardPolicy.DeviceSubscription(hostClipboard, shareOn, subscribed);
        bool wasSubscribed = subscribed;
        subscribed = now;
        switch (step)
        {
            case ClipboardPolicy.Subscription.Subscribe:
                log($"Clipboard: shared ({why}).");
                Offer(ClipboardPolicy.Subscribing, isText: false);
                if (inFront()) Look();
                break;
            case ClipboardPolicy.Subscription.Stop:
                log($"Clipboard: stopped sharing ({why}).");
                outbox.Stop(); later.Stop();
                send(ClipboardPolicy.Message(ClipboardPolicy.Stopping));   // past the rate, as the Mac takes it
                break;
            default:
                if (wasSubscribed && !now) log("Clipboard: the Mac stopped sharing its clipboard.");
                break;
        }
    }

    /// <summary>A kind 32 from the Mac: its text onto Windows' clipboard.</summary>
    public void Received(byte[] payload)
    {
        if (ClipboardPolicy.DeviceWrites(payload, shareOn, hostClipboard, lastSent, GetClipboardSequenceNumber()) is not { } text)
        {
            log($"Clipboard: {payload.Length} B from the Mac not written.");
            return;
        }
        if (!Write(text)) { log("Clipboard: couldn’t open Windows' clipboard; the Mac's text wasn't written."); return; }
        ownSequence = handled = GetClipboardSequenceNumber();
        log($"Clipboard: wrote {System.Text.Encoding.UTF8.GetByteCount(text)} B of text from the Mac.");
    }

    /// <summary>The viewer came to the front: a copy made while it wasn't goes now.</summary>
    public void CameToFront() => Look();

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_CLIPBOARDUPDATE && inFront()) Look();
        base.WndProc(ref m);
    }

    // A change of Windows' clipboard not yet dealt with: decided, and sent if it goes. Not again
    // from inside itself: reading the clipboard waits on its owner, and Windows delivers the window's
    // sent messages meanwhile (WM_CLIPBOARDUPDATE, the form's activation), which sent one copy twice.
    private bool looking;
    private void Look()
    {
        // A copy made while this one was read was let go by the guard: looked at next.
        if (LookOnce() && GetClipboardSequenceNumber() != handled && inFront())
            SynchronizationContext.Current?.Post(_ => Look(), null);
    }

    /// <summary>True when a change was decided.</summary>
    private bool LookOnce()
    {
        uint sequence = GetClipboardSequenceNumber();
        if (looking || !subscribed || sequence == handled) return false;
        looking = true;
        byte[]? payload; ClipboardPolicy.Skip? why; string? read = null;
        try
        {
            if (!OpenClipboardWithRetry()) return false;   // another app holds it: the next change or activation looks again
            try
            {
                (payload, why) = ClipboardPolicy.PcDecides(sequence, ownSequence, IsClipboardFormatAvailable(ExcludeFormat),
                    ReadDword(HistoryFormat), ReadDword(CloudFormat), () => read = ReadText(), lastSent, clock.Elapsed.TotalSeconds);
            }
            finally { CloseClipboard(); }
        }
        finally { looking = false; }
        handled = sequence;
        if (payload is null)
        {
            if (why != ClipboardPolicy.Skip.Own)
                log(why switch
                {
                    ClipboardPolicy.Skip.Repeat => $"Clipboard: change {sequence}, the copy just sent again; not sent.",
                    ClipboardPolicy.Skip.Marked => $"Clipboard: change {sequence}, a copy its app keeps private; not sent.",
                    ClipboardPolicy.Skip.TooLong => $"Clipboard: change {sequence}, a copy over {Sill.Protocol.Clipboard.MaxTextBytes / 1024} KB; not sent.",
                    _ => $"Clipboard: change {sequence}, a copy with no text; not sent.",
                });
            return true;
        }
        lastSent = new ClipboardPolicy.Sent(read!, sequence, clock.Elapsed.TotalSeconds);
        log($"Clipboard: change {sequence} goes to the Mac.");
        Offer(payload, isText: true);
        return true;
    }

    private void Offer(byte[] payload, bool isText)
    {
        if (outbox.Offer(payload, isText, clock.Elapsed.TotalSeconds) is { } now) Go(now);
        else Schedule();
    }

    private void Flush()
    {
        if (outbox.Due(clock.Elapsed.TotalSeconds) is { } now) Go(now);
        Schedule();
    }

    private void Schedule()
    {
        if (outbox.NextAt is not { } at || later.Enabled) return;
        later.Interval = Math.Max(1, (int)Math.Ceiling((at - clock.Elapsed.TotalSeconds) * 1000));
        later.Start();
    }

    private void Go(byte[] payload)
    {
        send(ClipboardPolicy.Message(payload));
        if (payload.Length > 2) log($"Clipboard: sent {payload.Length} B to the Mac.");
    }

    // ---- Windows' clipboard ----

    private bool OpenClipboardWithRetry()
    {
        for (int i = 0; i < 10; i++)
        {
            if (OpenClipboard(Handle)) return true;
            Thread.Sleep(10);
        }
        return false;
    }

    private static uint? ReadDword(uint format)
    {
        if (!IsClipboardFormatAvailable(format) || GetClipboardData(format) is var h && h == IntPtr.Zero) return null;
        var p = GlobalLock(h);
        try { return p == IntPtr.Zero || (long)GlobalSize(h) < 4 ? null : (uint)Marshal.ReadInt32(p); }
        finally { if (p != IntPtr.Zero) GlobalUnlock(h); }
    }

    private static string? ReadText()
    {
        if (!IsClipboardFormatAvailable(CF_UNICODETEXT) || GetClipboardData(CF_UNICODETEXT) is var h && h == IntPtr.Zero) return null;
        var p = GlobalLock(h);
        if (p == IntPtr.Zero) return null;
        try
        {
            int chars = (int)((long)GlobalSize(h) / 2);
            var s = Marshal.PtrToStringUni(p, chars);
            int end = s.IndexOf('\0');
            return end >= 0 ? s[..end] : s;
        }
        finally { GlobalUnlock(h); }
    }

    // The Mac's text, as the iPad writes it local-only: kept out of Windows' cloud clipboard (its
    // history may keep it).
    private bool Write(string text)
    {
        if (!OpenClipboardWithRetry()) return false;
        try
        {
            if (!EmptyClipboard()) return false;
            var chars = (text + "\0").ToCharArray();
            return Put(CF_UNICODETEXT, h => Marshal.Copy(chars, 0, h, chars.Length), chars.Length * 2)
                   && Put(CloudFormat, h => Marshal.WriteInt32(h, 0), 4);
        }
        finally { CloseClipboard(); }
    }

    private static bool Put(uint format, Action<IntPtr> fill, int bytes)
    {
        const uint GMEM_MOVEABLE = 0x0002;
        var h = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes);
        if (h == IntPtr.Zero) return false;
        var p = GlobalLock(h);
        if (p == IntPtr.Zero) { GlobalFree(h); return false; }
        fill(p);
        GlobalUnlock(h);
        if (SetClipboardData(format, h) != IntPtr.Zero) return true;   // Windows owns it now
        GlobalFree(h);
        return false;
    }

    public void Dispose()
    {
        later.Dispose();
        if (Handle != IntPtr.Zero) { RemoveClipboardFormatListener(Handle); DestroyHandle(); }
    }

    [DllImport("user32.dll", SetLastError = true)] private static extern bool AddClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool RemoveClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterClipboardFormat(string name);
    [DllImport("user32.dll")] private static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll")] private static extern bool CloseClipboard();
    [DllImport("user32.dll")] private static extern bool EmptyClipboard();
    [DllImport("user32.dll")] private static extern bool IsClipboardFormatAvailable(uint format);
    [DllImport("user32.dll")] private static extern IntPtr GetClipboardData(uint format);
    [DllImport("user32.dll")] private static extern IntPtr SetClipboardData(uint format, IntPtr data);
    [DllImport("kernel32.dll")] private static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll")] private static extern IntPtr GlobalFree(IntPtr h);
    [DllImport("kernel32.dll")] private static extern IntPtr GlobalLock(IntPtr h);
    [DllImport("kernel32.dll")] private static extern bool GlobalUnlock(IntPtr h);
    [DllImport("kernel32.dll")] private static extern UIntPtr GlobalSize(IntPtr h);
}
