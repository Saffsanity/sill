using D = Sill.Protocol.DataFolder;

namespace Sill.Protocol.Tests;

/// <summary>Ticket 10d: the data folder, <c>%LOCALAPPDATA%\Sill</c>, and the move up from the spike's.</summary>
public class DataFolderTests
{
    private const string Local = @"C:\Users\jo\AppData\Local";
    private static readonly string[] SpikeFiles = ["device.p12", "macs.json", "mac.json.migrated", "pc.json", "window.json", "viewer.log"];

    [Fact]
    public void Paths()
    {
        Assert.Equal(@"C:\Users\jo\AppData\Local\Sill", D.Root(Local));
        Assert.Equal(@"C:\Users\jo\AppData\Local\Sill", D.Root(Local + @"\"));
        Assert.Equal(@"C:\Users\jo\AppData\Local\Sill\spike", D.SpikeDir(Local));
        // One folder for everything: the update check's state and the install offer's sit in it.
        Assert.Equal(D.Root(Local), UpdatePolicy.StateDirectory(Local, null));
        Assert.Equal(D.Root(Local) + @"\install.json", SelfInstallPolicy.StatePath(Local));
    }

    [Fact]
    public void AFreshInstallMovesNothing()
    {
        Assert.Equal(new D.Plan(D.Use.Data, []), D.Decide(false, false, [], []));
        Assert.Equal(D.Use.Data, D.Decide(false, false, [], ["install.json", "update.json"]).Use);
    }

    [Fact]
    public void TheSpikeAloneMovesUp()
    {
        var plan = D.Decide(false, true, SpikeFiles, []);
        Assert.Equal(D.Use.Migrate, plan.Use);
        Assert.Equal(["device.p12", "macs.json", "pc.json", "window.json", "viewer.log"], plan.Files);   // mac.json.migrated stays
        // The spike's mac.json, never taken in, moves too: macs.json is made from it in the new folder.
        Assert.Equal(["device.p12", "mac.json"], D.Decide(false, true, ["mac.json", "device.p12", "frame.png"], []).Files);
        // An empty spike folder is still renamed.
        var empty = D.Decide(false, true, [], []);
        Assert.Equal(D.Use.Migrate, empty.Use);
        Assert.Empty(empty.Files);
    }

    [Fact]
    public void ANewFolderWithAPairingTakesNothing()
    {
        Assert.Equal(new D.Plan(D.Use.Data, []), D.Decide(false, true, SpikeFiles, ["device.p12"]));
        Assert.Equal(D.Use.Data, D.Decide(false, true, SpikeFiles, ["macs.json", "update.json"]).Use);
        Assert.Equal(D.Use.Data, D.Decide(false, true, SpikeFiles, ["MACS.JSON"]).Use);   // Windows' case
    }

    [Fact]
    public void APartlyFilledNewFolderKeepsItsFiles()
    {
        // The update check and the install offer wrote into %LOCALAPPDATA%\Sill before this build.
        var plan = D.Decide(false, true, [.. SpikeFiles, "update.json"], ["update.json", "update.log", "install.json", "Window.json"]);
        Assert.Equal(D.Use.Migrate, plan.Use);
        Assert.Equal(["device.p12", "macs.json", "pc.json", "viewer.log"], plan.Files);
    }

    [Fact]
    public void ATestFolderIsNeverMigrated()
    {
        Assert.Equal(new D.Plan(D.Use.Test, []), D.Decide(true, true, SpikeFiles, []));
        Assert.Equal(new D.Opened(@"C:\t\id", null), D.Open(Local, @"C:\t\id"));
    }

    [Fact]
    public void TheOldFolderTakesAFreeName()
    {
        Assert.Equal("spike.migrated", D.MigratedName(["spike", "install.json"]));
        Assert.Equal("spike.migrated 2", D.MigratedName(["spike", "Spike.Migrated"]));
        Assert.Equal("spike.migrated 3", D.MigratedName(["spike.migrated", "spike.migrated 2"]));
    }

    // The move on real folders.

    private static string TempRoot()
    {
        var root = Path.Combine(Path.GetTempPath(), "sill-data-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(root, "spike"));
        return root;
    }

    private static void Write(string dir, string name, string text) { Directory.CreateDirectory(dir); File.WriteAllText(Path.Combine(dir, name), text); }

    [Fact]
    public void MoveUpMovesAndRenames()
    {
        var root = TempRoot();
        try
        {
            var spike = Path.Combine(root, "spike");
            foreach (var f in SpikeFiles) Write(spike, f, "spike " + f);
            Write(root, "update.json", "new update");
            var opened = D.MoveUp(spike, root);
            Assert.Equal(root, opened.Directory);
            Assert.Contains("moved device.p12, macs.json, pc.json, window.json, viewer.log", opened.Line);
            Assert.Equal("spike device.p12", File.ReadAllText(Path.Combine(root, "device.p12")));
            Assert.Equal("new update", File.ReadAllText(Path.Combine(root, "update.json")));
            Assert.False(Directory.Exists(spike));
            var old = Path.Combine(root, "spike.migrated");
            Assert.Equal(["mac.json.migrated"], Directory.GetFiles(old).Select(Path.GetFileName));
            Assert.Empty(Directory.GetFiles(root, "*.migrating"));
            // The next start finds the new folder paired and moves nothing.
            Assert.Equal(new D.Opened(root, null), D.MoveUp(spike, root));
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public void MoveUpLeavesBothAloneOnceTheNewFolderIsPaired()
    {
        var root = TempRoot();
        try
        {
            var spike = Path.Combine(root, "spike");
            Write(spike, "device.p12", "old");
            Write(root, "device.p12", "new");
            Assert.Equal(new D.Opened(root, null), D.MoveUp(spike, root));
            Assert.Equal("old", File.ReadAllText(Path.Combine(spike, "device.p12")));
            Assert.Equal("new", File.ReadAllText(Path.Combine(root, "device.p12")));
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public void AFailedMoveKeepsTheSpikeFolderWhole()
    {
        var root = TempRoot();
        try
        {
            var spike = Path.Combine(root, "spike");
            Write(spike, "device.p12", "key");
            Write(spike, "macs.json", "macs");
            Write(spike, "pc.json", "name");
            // macs.json can't be copied across: a folder sits where its copy would go, after device.p12 was placed.
            Directory.CreateDirectory(Path.Combine(root, "macs.json.migrating"));
            var opened = D.MoveUp(spike, root);
            Assert.Equal(spike, opened.Directory);
            Assert.Contains("couldn’t move", opened.Line);
            Assert.Equal(["device.p12", "macs.json", "pc.json"], Directory.GetFiles(spike).Select(Path.GetFileName).Order());
            Assert.False(File.Exists(Path.Combine(root, "device.p12")));
            Assert.False(File.Exists(Path.Combine(root, "macs.json")));
            Assert.Empty(Directory.GetFiles(root, "*.migrating"));
            Assert.False(Directory.Exists(Path.Combine(root, "spike.migrated")));
            // Once what was in the way is gone, the next start moves it all.
            Directory.Delete(Path.Combine(root, "macs.json.migrating"));
            Assert.Equal(root, D.MoveUp(spike, root).Directory);
            Assert.Equal("macs", File.ReadAllText(Path.Combine(root, "macs.json")));
        }
        finally { Directory.Delete(root, true); }
    }
}
