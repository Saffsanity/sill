using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Sill.Viewer;

/// <summary>
/// A low-level keyboard hook (WH_KEYBOARD_LL), for the keys Windows keeps before any window sees
/// them: Alt+Tab and the Windows key. The callback runs on the thread that installed it (the UI
/// thread, whose message loop drives it) and returns true to keep a key from Windows.
/// </summary>
sealed class KeyboardHook : IDisposable
{
    public delegate bool Handler(int virtualKey, bool down, bool altDown);

    private const int WH_KEYBOARD_LL = 13, WM_KEYDOWN = 0x100, WM_SYSKEYDOWN = 0x104, LLKHF_ALTDOWN = 0x20, LLKHF_INJECTED = 0x10;
    private readonly HookProc proc;   // kept alive: Windows calls it for as long as the hook is set
    private readonly Handler handler;
    private IntPtr hook;

    public KeyboardHook(Handler handler)
    {
        this.handler = handler;
        proc = Callback;
        hook = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0);
        if (hook == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    private IntPtr Callback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var k = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
            bool down = wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN;
            if ((k.Flags & LLKHF_INJECTED) == 0 && handler((int)k.VkCode, down, (k.Flags & LLKHF_ALTDOWN) != 0)) return 1;
        }
        return CallNextHookEx(hook, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (hook != IntPtr.Zero) { UnhookWindowsHookEx(hook); hook = IntPtr.Zero; }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KbdLlHookStruct { public uint VkCode, ScanCode, Flags, Time; public IntPtr ExtraInfo; }

    private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int idHook, HookProc proc, IntPtr module, uint threadId);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string? name);
}
