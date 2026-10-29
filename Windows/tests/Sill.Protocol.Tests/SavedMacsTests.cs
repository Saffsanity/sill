using System.Security.Cryptography;

namespace Sill.Protocol.Tests;

public class SavedMacsTests
{
    private static SavedMac Mac(string seed, string name = "Mac mini", int day = 0, bool? newKey = null)
    {
        var key = SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(seed));
        return new SavedMac(Base64Url.Encode(key), MacId.Make(key), name, Base64Url.Encode(Enumerable.Repeat((byte)0x11, 32).ToArray()),
                            "192.168.1.5", 49880, DateTimeOffset.UnixEpoch.AddDays(day), NewKey: newKey);
    }

    private static string TempDir() => Path.Combine(Path.GetTempPath(), "sill-macs-" + Guid.NewGuid().ToString("N"));

    [Fact]
    public void AddingReplacesTheSameMacAndPutsItLast()
    {
        var a = Mac("a"); var b = Mac("b");
        var list = SavedMacs.Adding(a with { Name = "renamed" }, SavedMacs.Adding(b, SavedMacs.Adding(a, [])));
        Assert.Equal([b.MacId, a.MacId], list.Select(m => m.MacId));
        Assert.Equal("renamed", SavedMacs.Newest(list)!.Name);
    }

    [Fact]
    public void AddingKeepsTheCap()
    {
        IReadOnlyList<SavedMac> list = [];
        for (int i = 0; i < SavedMacs.Cap + 3; i++) list = SavedMacs.Adding(Mac($"m{i}", day: i), list);
        Assert.Equal(SavedMacs.Cap, list.Count);
        Assert.DoesNotContain(list, m => m.MacId == Mac("m0").MacId);
    }

    [Fact]
    public void ANewKeyMarkAndTheReplacement()
    {
        var old = Mac("old"); var other = Mac("other"); var fresh = Mac("fresh");
        Assert.Null(SavedMacs.MarkingNewKey("nobody", [old]));
        var marked = SavedMacs.MarkingNewKey(old.MacId, [old, other])!;
        Assert.True(marked[0].NewKey);
        Assert.Null(SavedMacs.MarkingNewKey(old.MacId, marked));   // already
        // Replaced only once the new Mac is saved, and only a marked record.
        Assert.Equal(2, SavedMacs.ReplacingNewKey(old.MacId, fresh.MacId, marked).Count);
        var withFresh = SavedMacs.Adding(fresh, marked);
        Assert.Equal([other.MacId, fresh.MacId], SavedMacs.ReplacingNewKey(old.MacId, fresh.MacId, withFresh).Select(m => m.MacId));
        Assert.Equal(3, SavedMacs.ReplacingNewKey(other.MacId, fresh.MacId, withFresh).Count);
        Assert.Equal(withFresh, SavedMacs.ReplacingNewKey(old.MacId, old.MacId, withFresh));
        Assert.Equal([other.MacId, fresh.MacId], SavedMacs.Forgetting(old.MacId, withFresh).Select(m => m.MacId));
    }

    [Fact]
    public void TheFileTakesInTheSpikesMacJsonOnce()
    {
        string dir = TempDir();
        Directory.CreateDirectory(dir);
        try
        {
            // As Sill.Spike pair wrote it.
            var a = Mac("a");
            File.WriteAllText(Path.Combine(dir, "mac.json"),
                $$"""{"Fingerprint":"{{a.Fingerprint}}","MacId":"{{a.MacId}}","Name":"Mac mini","RecognitionKey":"{{a.RecognitionKey}}","Host":"127.0.0.1","Port":47455,"PairedAt":"2026-10-19T10:00:00+00:00"}""");
            var store = new SavedMacsFile(dir);
            var loaded = Assert.Single(store.Load());
            Assert.Equal((a.MacId, "127.0.0.1", 47455), (loaded.MacId, loaded.Host, loaded.Port));
            Assert.True(File.Exists(Path.Combine(dir, "macs.json")));
            Assert.False(File.Exists(Path.Combine(dir, "mac.json")));
            Assert.True(File.Exists(Path.Combine(dir, "mac.json.migrated")));
            Assert.Single(new SavedMacsFile(dir).Load());
        }
        finally { Directory.Delete(dir, recursive: true); }
    }

    [Fact]
    public void TheFileRoundTripsAndForgets()
    {
        string dir = TempDir();
        try
        {
            ISavedMacs store = new SavedMacsFile(dir);
            Assert.Empty(store.Load());
            var a = Mac("a"); var b = Mac("b", "Studio");
            store.Add(a);
            store.Add(b with { BonjourName = "Studio (2)" });
            store.MarkNewKey(a.MacId);
            var again = new SavedMacsFile(dir).Load();
            Assert.Equal([a.MacId, b.MacId], again.Select(m => m.MacId));
            Assert.True(again[0].NewKey);
            Assert.Equal("Studio (2)", again[1].BonjourName);
            Assert.True(again[0].Known.NewKey);
            Assert.Equal(32, again[0].Known.RecognitionKey!.Length);
            store.Forget(a.MacId);
            Assert.Equal([b.MacId], new SavedMacsFile(dir).Load().Select(m => m.MacId));
        }
        finally { Directory.Delete(dir, recursive: true); }
    }

    [Fact]
    public void AFileThatDoesntParseReadsAsNoneAndIsKeptAside()
    {
        string dir = TempDir();
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "macs.json"), "{ not json");
            var store = new SavedMacsFile(dir);
            Assert.Empty(store.Load());
            store.Add(Mac("a"));
            Assert.True(File.Exists(Path.Combine(dir, "macs.json.bad")));
            Assert.Single(new SavedMacsFile(dir).Load());
        }
        finally { Directory.Delete(dir, recursive: true); }
    }

    [Fact]
    public void ThisPcsName()
    {
        string dir = TempDir();
        try
        {
            Assert.Equal("MSI", ThisPc.Load(dir).NameOr("MSI"));
            new ThisPc("  Jericho’s‮\nlaptop  ").Save(dir);
            Assert.Equal("Jericho’s laptop", ThisPc.Load(dir).NameOr("MSI"));
            new ThisPc("   ").Save(dir);
            Assert.Equal("MSI", ThisPc.Load(dir).NameOr("MSI"));
            Assert.Equal("Windows PC", new ThisPc(null).NameOr(""));
            Assert.Equal(64, ThisPc.Clean(new string('x', 100)).Length);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true); }
    }
}
