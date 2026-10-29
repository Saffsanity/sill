namespace Sill.Viewer;

/// <summary>
/// The window Direct3D draws the Mac's picture into (a swap chain on its handle), under the bar
/// and the Apps drawer. It takes no focus and no mouse: hit-testing passes through it to the
/// form, so the form's input code serves both the GPU and the software paths.
/// </summary>
sealed class VideoPanel : Control
{
    public VideoPanel()
    {
        SetStyle(ControlStyles.Selectable, false);
        // Nothing of GDI's ever paints here (it would flicker over the swap chain).
        SetStyle(ControlStyles.Opaque | ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint, true);
        TabStop = false;
        BackColor = Color.Black;
    }

    protected override void OnPaint(PaintEventArgs e) { }
    protected override void OnPaintBackground(PaintEventArgs e) { }

    protected override void WndProc(ref Message m)
    {
        const int WM_NCHITTEST = 0x0084, HTTRANSPARENT = -1;
        if (m.Msg == WM_NCHITTEST) { m.Result = HTTRANSPARENT; return; }
        base.WndProc(ref m);
    }
}
