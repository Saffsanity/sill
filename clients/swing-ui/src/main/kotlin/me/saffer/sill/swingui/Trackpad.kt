package me.saffer.sill.swingui

import me.saffer.sill.core.ui.Copy
import me.saffer.sill.core.ui.PadTracker
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Ui
import java.awt.Graphics
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.event.MouseWheelEvent
import java.awt.geom.Ellipse2D
import javax.swing.JComponent
import javax.swing.Timer

/**
 * The portrait trackpad (Trackpad in TrackpadView.swift): the well (Palette.trackpad, corners 22,
 * the white 8 % hairline, 1 pt dots on an 18 pt grid) with its hint at the foot, driving a
 * [PadTracker] as the iPad's fingers do. The mouse is one finger: a drag moves the pointer, a click
 * clicks, a hold of 0.45 s then a drag drags; the right button is two fingers' tap; the wheel is a
 * two-finger scroll, with the coast, ending 120 ms after its last notch.
 */
class TrackpadWell(val tracker: PadTracker) : SillComponent() {
    private val ticker = Timer(16) { tracker.tick(now()); if (!tracker.needsTicks) stopTicks() }
    private var wheelFingers = false
    private var wheelX = 0.0; private var wheelY = 0.0
    private val wheelEnd = Timer(120) { endWheel() }.apply { isRepeats = false }

    init {
        isOpaque = false
        getAccessibleContext().accessibleName = Copy.trackpadHint
        toolTipText = null
        val m = object : MouseAdapter() {
            override fun mousePressed(e: MouseEvent) {
                endWheel()
                when (e.button) {
                    MouseEvent.BUTTON1 -> tracker.down(0, e.x.toDouble(), e.y.toDouble(), now())
                    MouseEvent.BUTTON3 -> { val t = now(); tracker.down(0, e.x.toDouble(), e.y.toDouble(), t); tracker.down(1, e.x + 12.0, e.y.toDouble(), t) }
                }
                ticks()
            }
            override fun mouseDragged(e: MouseEvent) { if (javax.swing.SwingUtilities.isLeftMouseButton(e)) tracker.move(0, e.x.toDouble(), e.y.toDouble(), now()); ticks() }
            override fun mouseReleased(e: MouseEvent) {
                val t = now()
                when (e.button) {
                    MouseEvent.BUTTON1 -> tracker.up(0, e.x.toDouble(), e.y.toDouble(), t)
                    MouseEvent.BUTTON3 -> { tracker.up(1, e.x + 12.0, e.y.toDouble(), t); tracker.up(0, e.x.toDouble(), e.y.toDouble(), t) }
                }
                ticks()
            }
            override fun mouseWheelMoved(e: MouseWheelEvent) {
                val t = now()
                if (!wheelFingers) {
                    wheelFingers = true; wheelX = width / 2.0; wheelY = height / 2.0
                    tracker.down(10, wheelX, wheelY, t); tracker.down(11, wheelX + 20, wheelY, t)
                }
                val d = -e.preciseWheelRotation * 40
                if (e.isShiftDown) wheelX += d else wheelY += d
                tracker.move(10, wheelX, wheelY, t); tracker.move(11, wheelX + 20, wheelY, t)
                wheelEnd.restart(); ticks()
            }
        }
        addMouseListener(m); addMouseMotionListener(m); addMouseWheelListener(m)
    }

    override fun setBounds(x: Int, y: Int, width: Int, height: Int) {
        super.setBounds(x, y, width, height)
        tracker.width = width.toDouble(); tracker.height = height.toDouble()
    }

    private fun endWheel() {
        if (!wheelFingers) return
        wheelFingers = false
        val t = now()
        tracker.up(11, wheelX + 20, wheelY, t); tracker.up(10, wheelX, wheelY, t)
        ticks()
    }

    private fun ticks() { if (tracker.needsTicks && !ticker.isRunning) ticker.start() }
    private fun stopTicks() { ticker.stop() }
    private fun now() = System.nanoTime() / 1e9

    override fun removeNotify() { ticker.stop(); wheelEnd.stop(); if (tracker.isDragging || wheelFingers) tracker.cancel(); super.removeNotify() }

    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val r = Rect(0.0, 0.0, width.toDouble(), height.toDouble())
        val clip = g.clip
        g.clip(SillSwing.round(r, Ui.padCorner))
        SillSwing.fill(g, r, 0.0, Palette.trackpad)
        g.color = SillSwing.color(Rgba.white.opacity(Ui.padDotAlpha))
        val step = Ui.padDotStep; val d = Ui.padDotRadius * 2
        var y = step / 2
        while (y < height) { var x = step / 2; while (x < width) { g.fill(Ellipse2D.Double(x - d / 2, y - d / 2, d, d)); x += step }; y += step }
        val f = SillSwing.font(me.saffer.sill.core.ui.TextStyle(Ui.padHintSize))
        val lines = Wrap.lines(g.getFontMetrics(f), Copy.trackpadHint, width - 2 * Ui.padHintInset)
        val lh = g.getFontMetrics(f).height
        var ty = height - Ui.padHintInset - lines.size * lh
        for (l in lines) { SillSwing.centred(g, l, r, ty, f, Palette.muted); ty += lh }
        g.clip = clip
        SillSwing.strokeBorder(g, r, Ui.padCorner, Rgba.white.opacity(Ui.padStrokeAlpha))
        g.dispose()
    }
}
