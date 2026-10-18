using Sill.Protocol;

namespace Sill.Viewer;

/// <summary>
/// The Apps drawer: the Mac's installed apps (kind 5) with their icons (kind 4), a search field,
/// and a click that opens one (kind 7). While it is open its field takes the keys; closing it
/// gives them back to the Mac.
/// </summary>
sealed class AppsDrawer : Panel
{
    public event Action<string>? Launch;
    public event Action? Closed;

    private readonly TextBox search;
    private readonly ListView list;
    private readonly ImageList icons;
    private IReadOnlyList<AppInfo> apps = [];

    public AppsDrawer()
    {
        Dock = DockStyle.Left;
        Width = LogicalToDeviceUnits(340);
        BackColor = Color.FromArgb(28, 28, 30);
        Padding = new Padding(LogicalToDeviceUnits(8));
        Visible = false;

        search = new TextBox
        {
            Dock = DockStyle.Top, PlaceholderText = "Search apps", BorderStyle = BorderStyle.FixedSingle,
            BackColor = Color.FromArgb(44, 44, 46), ForeColor = Color.White, Font = new Font("Segoe UI", 11f),
        };

        icons = new ImageList { ImageSize = new Size(LogicalToDeviceUnits(28), LogicalToDeviceUnits(28)), ColorDepth = ColorDepth.Depth32Bit };
        list = new ListView
        {
            Dock = DockStyle.Fill, View = View.Details, HeaderStyle = ColumnHeaderStyle.None, FullRowSelect = true,
            SmallImageList = icons, BorderStyle = BorderStyle.None, BackColor = Color.FromArgb(28, 28, 30),
            ForeColor = Color.White, Font = new Font("Segoe UI", 10f), MultiSelect = false,
        };
        list.Columns.Add("", -2);
        list.ItemActivate += (_, _) => { if (list.SelectedItems.Count > 0) Open((string)list.SelectedItems[0].Tag!); };
        list.MouseClick += (_, e) => { if (list.GetItemAt(e.X, e.Y) is { } item) Open((string)item.Tag!); };
        list.Resize += (_, _) => list.Columns[0].Width = list.ClientSize.Width;
        search.TextChanged += (_, _) => Fill();
        search.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Escape) { e.SuppressKeyPress = true; Hide(); Closed?.Invoke(); }
            if (e.KeyCode == Keys.Enter && list.Items.Count > 0) { e.SuppressKeyPress = true; Open((string)list.Items[0].Tag!); }
        };

        Controls.Add(list);
        Controls.Add(new Panel { Dock = DockStyle.Top, Height = LogicalToDeviceUnits(8), BackColor = BackColor });
        Controls.Add(search);
    }

    public bool Typing => Visible && search.Focused;

    public void Toggle()
    {
        if (Visible) { Hide(); Closed?.Invoke(); return; }
        search.Text = "";
        Fill();
        Show();
        BringToFront();
        search.Focus();
    }

    public void SetApps(IReadOnlyList<AppInfo> apps) { this.apps = apps; if (Visible) Fill(); }

    public void SetIcon(string bundleId, Image image)
    {
        if (icons.Images.ContainsKey(bundleId)) icons.Images.RemoveByKey(bundleId);
        icons.Images.Add(bundleId, image);
        if (Visible) list.Invalidate();
    }

    private void Fill()
    {
        string q = search.Text.Trim();
        list.BeginUpdate();
        list.Items.Clear();
        foreach (var a in apps.Where(a => q.Length == 0 || a.Name.Contains(q, StringComparison.OrdinalIgnoreCase)).OrderBy(a => a.Name, StringComparer.OrdinalIgnoreCase))
            list.Items.Add(new ListViewItem(a.Name, a.BundleId) { Tag = a.BundleId });
        list.EndUpdate();
    }

    private void Open(string bundleId)
    {
        Launch?.Invoke(bundleId);
        Hide();
        Closed?.Invoke();
    }
}
