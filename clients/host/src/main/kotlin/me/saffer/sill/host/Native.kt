package me.saffer.sill.host

import java.lang.foreign.Arena
import java.lang.foreign.FunctionDescriptor
import java.lang.foreign.Linker
import java.lang.foreign.MemoryLayout
import java.lang.foreign.MemorySegment
import java.lang.foreign.SymbolLookup
import java.lang.foreign.ValueLayout
import java.lang.invoke.MethodHandle

/**
 * The operating system's own libraries through the JDK's foreign function API (java.lang.foreign):
 * Xlib and XTest on Linux, user32 on Windows. No JNI, no third-party binding. A handle is looked up
 * once and called with [call]; a function the library lacks is null, so a caller can do without it.
 */
internal class NativeLibrary(name: String) {
    private val linker = Linker.nativeLinker()
    private val lookup: SymbolLookup = SymbolLookup.libraryLookup(name, Arena.global())

    fun fn(symbol: String, ret: MemoryLayout?, vararg args: MemoryLayout): MethodHandle? {
        val addr = lookup.find(symbol).orElse(null) ?: return null
        return linker.downcallHandle(addr, if (ret == null) FunctionDescriptor.ofVoid(*args) else FunctionDescriptor.of(ret, *args))
    }

    fun need(symbol: String, ret: MemoryLayout?, vararg args: MemoryLayout): MethodHandle =
        fn(symbol, ret, *args) ?: throw UnsatisfiedLinkError("$symbol is not in the library")

    companion object {
        val ADDR: java.lang.foreign.AddressLayout = ValueLayout.ADDRESS
        val INT: ValueLayout.OfInt = ValueLayout.JAVA_INT
        val LONG: ValueLayout.OfLong = ValueLayout.JAVA_LONG
        val SHORT: ValueLayout.OfShort = ValueLayout.JAVA_SHORT
        val BYTE: ValueLayout.OfByte = ValueLayout.JAVA_BYTE
    }
}

internal fun MethodHandle.call(vararg args: Any?): Any? = invokeWithArguments(*args)
internal fun MethodHandle.int(vararg args: Any?): Int = (invokeWithArguments(*args) as Number).toInt()
internal fun MethodHandle.long(vararg args: Any?): Long = (invokeWithArguments(*args) as Number).toLong()
internal fun MethodHandle.ptr(vararg args: Any?): MemorySegment = invokeWithArguments(*args) as MemorySegment

internal fun MemorySegment.isNull() = address() == 0L
