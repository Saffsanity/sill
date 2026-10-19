package me.saffer.sill.android

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.lang.reflect.Proxy

/**
 * The fold, without AndroidX: the platform's own window extensions (the OEM library every foldable
 * with Android 12L and later ships, `androidx.window.extensions`, declared optional in the manifest),
 * else the older sidecar (`androidx.window.sidecar`, Samsung's foldables before it), else the hinge
 * angle sensor (API 30), else nothing. Every call is by reflection and guarded: a missing class, a
 * changed signature or a vendor's exception falls back to the next source, silently. What it reads
 * goes to `onChange` on the main thread, as FoldMapping's Reading; the mapping into the stream
 * screen's dp is FoldMapping's, tested on the JVM.
 */
class FoldReader(private val activity: Activity, private val onChange: (FoldMapping.Reading) -> Unit) {
    private var stop: (() -> Unit)? = null
    private var hingeSeen = false

    /** Starts listening (onStart or once the window is attached); idempotent. */
    fun start() {
        if (stop != null) return
        stop = tryExtensions() ?: trySidecar() ?: tryHinge()
        if (stop == null) post(FoldMapping.Reading.Nothing)
    }

    fun stop() {
        try { stop?.invoke() } catch (t: Throwable) { Log.d(TAG, "stop: $t") }
        stop = null
    }

    private fun post(r: FoldMapping.Reading) = activity.runOnUiThread { if (!activity.isDestroyed) onChange(r) }

    // MARK: The window extensions (vendor API level 1 and later)

    private fun tryExtensions(): (() -> Unit)? = try {
        val provider = Class.forName("androidx.window.extensions.WindowExtensionsProvider")
        val extensions = provider.getMethod("getWindowExtensions").invoke(null)!!
        val component = extensions.javaClass.getMethod("getWindowLayoutComponent").invoke(extensions)
            ?: throw IllegalStateException("no WindowLayoutComponent")
        val iface = Class.forName("androidx.window.extensions.layout.WindowLayoutComponent")
        val folding = Class.forName("androidx.window.extensions.layout.FoldingFeature")
        val handle = { info: Any? -> post(FoldMapping.Reading.Extensions(info?.let { feature(it, folding) })) }
        // Level 2 and later: Context and the extensions' own Consumer (an interface reached by Proxy).
        val core = try { Class.forName("androidx.window.extensions.core.util.function.Consumer") } catch (_: Throwable) { null }
        val added = core?.let { cls ->
            try {
                val consumer = Proxy.newProxyInstance(cls.classLoader, arrayOf(cls)) { proxy, method, args ->
                    when (method.name) {
                        "accept" -> { handle(args?.getOrNull(0)); null }
                        "equals" -> proxy === args?.getOrNull(0)
                        "hashCode" -> System.identityHashCode(proxy)
                        "toString" -> "SillFoldConsumer"
                        else -> null
                    }
                }
                iface.getMethod("addWindowLayoutInfoListener", Context::class.java, cls).invoke(component, activity, consumer)
                val remove = iface.getMethod("removeWindowLayoutInfoListener", cls)
                ({ remove.invoke(component, consumer); Unit })
            } catch (t: Throwable) { Log.d(TAG, "extensions (core consumer): $t"); null }
        }
        added ?: run {
            // Level 1: the Activity and java.util.function.Consumer.
            val consumer = java.util.function.Consumer<Any?> { handle(it) }
            iface.getMethod("addWindowLayoutInfoListener", Activity::class.java, java.util.function.Consumer::class.java).invoke(component, activity, consumer)
            val remove = iface.getMethod("removeWindowLayoutInfoListener", java.util.function.Consumer::class.java)
            ({ remove.invoke(component, consumer); Unit })
        }
    } catch (t: Throwable) { Log.d(TAG, "no window extensions: $t"); null }

    /** The first folding feature of a WindowLayoutInfo: its bounds and state (FLAT 1, HALF_OPENED 2), type HINGE (2) separating. */
    private fun feature(info: Any, folding: Class<*>): FoldMapping.Feature? = try {
        val features = info.javaClass.getMethod("getDisplayFeatures").invoke(info) as List<*>
        features.firstOrNull { folding.isInstance(it) }?.let { f ->
            val r = folding.getMethod("getBounds").invoke(f) as android.graphics.Rect
            val state = folding.getMethod("getState").invoke(f) as Int
            val type = folding.getMethod("getType").invoke(f) as Int
            FoldMapping.Feature(PxBox(r.left, r.top, r.right, r.bottom), halfOpened = state == 2, separating = type == 2)
        }
    } catch (t: Throwable) { Log.d(TAG, "a feature: $t"); null }

    // MARK: The sidecar (Samsung's foldables before the extensions)

    private fun trySidecar(): (() -> Unit)? = try {
        val sidecar = Class.forName("androidx.window.sidecar.SidecarProvider").getMethod("getSidecarImpl", Context::class.java)
            .invoke(null, activity.applicationContext) ?: throw IllegalStateException("no sidecar")
        val iface = Class.forName("androidx.window.sidecar.SidecarInterface")
        val callback = Class.forName("androidx.window.sidecar.SidecarInterface\$SidecarCallback")
        val token: IBinder = activity.window.decorView.windowToken ?: throw IllegalStateException("no window token yet")
        fun read() {
            try {
                val state = iface.getMethod("getDeviceState").invoke(sidecar)
                val posture = state?.javaClass?.getField("posture")?.getInt(state) ?: 0
                val layout = iface.getMethod("getWindowLayoutInfo", IBinder::class.java).invoke(sidecar, token)
                val features = layout?.javaClass?.getField("displayFeatures")?.get(layout) as? List<*>
                val f = features?.firstOrNull()
                val feature = f?.let {
                    val r = it.javaClass.getMethod("getRect").invoke(it) as android.graphics.Rect
                    val type = it.javaClass.getMethod("getType").invoke(it) as Int
                    FoldMapping.Feature(PxBox(r.left, r.top, r.right, r.bottom), halfOpened = posture == 2, separating = type == 2)
                }
                post(FoldMapping.Reading.Extensions(feature))
            } catch (t: Throwable) { Log.d(TAG, "sidecar read: $t") }
        }
        val proxy = Proxy.newProxyInstance(callback.classLoader, arrayOf(callback)) { p, method, args ->
            when (method.name) {
                "onDeviceStateChanged", "onWindowLayoutChanged" -> { read(); null }
                "equals" -> p === args?.getOrNull(0)
                "hashCode" -> System.identityHashCode(p)
                "toString" -> "SillSidecarCallback"
                else -> null
            }
        }
        iface.getMethod("setSidecarCallback", callback).invoke(sidecar, proxy)
        iface.getMethod("onWindowLayoutChangeListenerAdded", IBinder::class.java).invoke(sidecar, token)
        read()
        ({ iface.getMethod("onWindowLayoutChangeListenerRemoved", IBinder::class.java).invoke(sidecar, token); Unit })
    } catch (t: Throwable) { Log.d(TAG, "no sidecar: $t"); null }

    // MARK: The hinge angle (API 30), a band down the middle of the longer side while half-open

    private fun tryHinge(): (() -> Unit)? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val sm = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
            val sensor = sm.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE) ?: return null
            val listener = object : SensorEventListener {
                private var half: Boolean? = null
                override fun onSensorChanged(e: SensorEvent) {
                    hingeSeen = true
                    // Only a change between half-open and not lays the screen out again.
                    val now = e.values[0] in FoldMapping.halfOpenFrom..FoldMapping.halfOpenTo
                    if (now != half) { half = now; post(FoldMapping.Reading.HingeAngle(e.values[0])) }
                }
                override fun onAccuracyChanged(s: Sensor?, a: Int) {}
            }
            if (!sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)) return null
            if (!hingeSeen) post(FoldMapping.Reading.Nothing)
            ({ sm.unregisterListener(listener) })
        } catch (t: Throwable) { Log.d(TAG, "no hinge sensor: $t"); null }
    }

    companion object { private const val TAG = "SillFold" }
}
