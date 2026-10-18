using System.Runtime.InteropServices;

namespace Sill.Media;

/// <summary>
/// COM by vtable slot, so nothing needs an interop package. Slots are the order of methods in the
/// Windows SDK's headers (IUnknown 0–2, then each interface's own after its parents').
/// </summary>
internal static unsafe class Com
{
    public static void* Slot(IntPtr obj, int slot) => (*(void***)obj)[slot];

    public static void Release(IntPtr obj)
    {
        if (obj != IntPtr.Zero) ((delegate* unmanaged[Stdcall]<IntPtr, uint>)Slot(obj, 2))(obj);
    }

    public static void AddRef(IntPtr obj) => ((delegate* unmanaged[Stdcall]<IntPtr, uint>)Slot(obj, 1))(obj);

    public static IntPtr Query(IntPtr obj, Guid iid)
    {
        IntPtr result;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, IntPtr*, int>)Slot(obj, 0))(obj, &iid, &result), "QueryInterface");
        return result;
    }

    public static void Check(int hr, string what, int? allow = null)
    {
        if (hr < 0 && hr != allow) throw new COMException($"{what} failed (0x{hr:X8})", hr);
    }
}
