// The Windows client spike (.scratch/windows-integration/map.md): pair with a Mac running
// `SillHost --pairing`, open a session, and write the first keyframe's decoded frame to a PNG.
// Ticket 03 added pairing, ticket 04 the session; ticket 05 the decoder.
//
//   Sill.Spike pair --host <address>:<port> --code <12 digits>
//   Sill.Spike pair --link '<sill://pair?…>' [--host <address>:<port>]
//   Sill.Spike pair --ask 1 --host <address>:<port>   (Sill.app opens its code window; type the code here)
//   Sill.Spike session [--seconds 10] [--host <address>:<port>] [--save <dir>] [--png <file>] [--decode 1 [--gpu 1] [--adapter N]]
//   Sill.Spike decode --input <first-keyframe.h265> --out <frame.png> [--gpu 1 [--adapter N] [--compare 1]]
//
// Options: --identity <dir> (default %LOCALAPPDATA%\Sill\spike), --name <device name>.
// A pairing saves the Mac in <dir>\macs.json; a session dials the newest (or --host), pinned to its key,
// asks for the Desktop and logs what arrives; --save writes the first keyframe's parameter sets
// and access unit, --png decodes it (ticket 05); decode does the same from a saved file.
// Exit: 0 paired (or a session that got a keyframe), 1 refused, unproven or no keyframe,
// 2 usage, 3 connection or TLS failure.

using System.Text.Json;
using Sill.Protocol;

return await Spike.RunAsync(args);

static class Spike
{
    public static async Task<int> RunAsync(string[] args)
    {
        // The Mac's words carry typographic quotes, ellipses and no-break spaces; a console on
        // its OEM code page (cmd, an SSH session) would print them as ?.
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        if (args.Length > 0 && args[0] == "decode") return DecodeCommand.Run(Options(args[1..]));
        if (args.Length == 0 || args[0] is not ("pair" or "session"))
            return Usage("Sill.Spike pair (--code <digits> --host <address>:<port> | --link <url> [--host <address>:<port>])\n"
                       + "Sill.Spike session [--seconds <n>] [--host <address>:<port>] [--save <dir>] [--png <file>]\n"
                       + "Sill.Spike decode --input <file.h265> --out <file.png>");
        var opts = Options(args[1..]);
        if (opts is null) return Usage("Every option takes a value.");
        string dir = opts.GetValueOrDefault("identity")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sill", "spike");
        string name = opts.GetValueOrDefault("name") ?? Environment.MachineName;
        return args[0] == "pair" ? await PairAsync(opts, dir, name) : await SessionCommand.RunAsync(opts, dir, name);
    }

    private static async Task<int> PairAsync(Dictionary<string, string> opts, string dir, string name)
    {
        byte[]? pinnedAsk = null;
        string? code = opts.GetValueOrDefault("code"), url = opts.GetValueOrDefault("link"), hostArg = opts.GetValueOrDefault("host");
        bool ask = opts.ContainsKey("ask");
        if (ask && url is null && code is null)
        {
            if (hostArg is null || !SplitHost(hostArg, out string askHost, out int askPort)) return Usage("--ask needs --host <address>:<port> (the Mac's home door).");
            using var askIdentity = DeviceIdentity.LoadOrCreate(dir);
            Console.WriteLine($"Asking {askHost}:{askPort} to show its pairing code…");
            PairResult? answer; byte[] askedKey;
            try { (answer, askedKey) = await PairingClient.AskAsync(askHost, askPort, askIdentity, name, "Windows", CancellationToken.None); }
            catch (Exception e) { Console.Error.WriteLine($"Couldn’t ask: {e.Message}"); return 3; }
            string askedMac = answer?.Name ?? "The Mac";
            if (answer?.Reason != PairResult.Shown)
            {
                Console.WriteLine(answer is null ? "The Mac didn’t answer the ask." : PairingExchange.Words(answer, askedMac));
                return 1;
            }
            Console.Write($"{PairingExchange.Words(answer, askedMac)} Type it here: ");
            code = opts.GetValueOrDefault("code-from") is { } file ? WaitForFile(file) : Console.ReadLine() ?? "";
            pinnedAsk = askedKey;
        }
        if ((code is null) == (url is null)) return Usage("Give --code, --link or --ask, one of them.");

        PairLink? link = null;
        if (url is not null)
        {
            var failure = PairLink.Parse(url, out link, out string? field);
            if (failure != PairLink.Failure.None) return Usage($"That link isn’t a Sill pairing link ({failure}{(field is null ? "" : $": {field}")}).");
        }
        else
        {
            var problem = PairingCode.Check(code!, out string digits);
            if (problem == PairingCode.Problem.Length) return Usage("The code is 12 digits.");
            if (problem == PairingCode.Problem.Typo) return Usage("That code has a typo. Check it against the code on your Mac.");
            code = digits;
        }

        string host; int port;
        if (hostArg is not null)
        {
            if (!SplitHost(hostArg, out host, out port)) return Usage("--host takes <address>:<port>.");
        }
        else if (link is { Addresses.Count: > 0 }) { host = link.Addresses[0]; port = link.Port; }
        else return Usage(link is null ? "The typed code needs --host <address>:<port>." : "This link names no address: add --host.");

        using var identity = DeviceIdentity.LoadOrCreate(dir);
        Console.WriteLine($"This device: {name}, key {Base64Url.Encode(identity.Fingerprint)[..10]}… ({Path.Combine(dir, DeviceIdentity.FileName)})");
        Console.WriteLine($"Pairing with {host}:{port} by {(link is null ? "typed code" : "link")}…");

        PairingClient.Outcome outcome;
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        try
        {
            outcome = link is null
                ? await PairingClient.PairWithCodeAsync(host, port, code!, identity, name, "Windows", cts.Token, pinnedAsk)
                : await PairingClient.PairWithLinkAsync(host, port, link, identity, name, "Windows", cts.Token);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"Couldn’t pair: {e.Message}");
            return 3;
        }

        string mac = link?.Name ?? outcome.Result?.Name ?? "The Mac";
        switch (outcome.Verdict)
        {
            case PairingExchange.Verdict.Paired:
                var r = outcome.Result!;
                var saved = new SavedMac(Base64Url.Encode(outcome.MacFingerprint), r.MacId!, SafeText.Label(r.Name ?? mac, 64),
                                         r.RecognitionKey!, host, port, DateTimeOffset.UtcNow);
                new SavedMacsFile(dir).Add(saved);
                Console.WriteLine($"Paired with {saved.Name} ({saved.MacId}); its proof checked. Saved to {Path.Combine(dir, SavedMacsFile.FileName)}.");
                return 0;
            case PairingExchange.Verdict.Refused:
                Console.WriteLine(PairingExchange.Words(outcome.Result!, mac));
                var refused = outcome.Result!;
                Console.WriteLine($"  (reason: {refused.Reason ?? "none"}{(refused.RetryAfter is { } after ? $", retry after {after:0.#} s" : "")})");
                return 1;
            default:
                Console.WriteLine($"{mac} said yes but didn’t prove it holds its key or the code ({outcome.Verdict}); nothing saved.");
                return 1;
        }
    }

    // For a run with no console (over SSH): the code arrives in a file instead of on stdin.
    private static string WaitForFile(string path)
    {
        Console.WriteLine();
        Console.WriteLine($"(waiting for the code in {path})");
        for (int i = 0; i < 600 && !File.Exists(path); i++) Thread.Sleep(500);
        return File.Exists(path) ? File.ReadAllText(path).Trim() : "";
    }

    internal static Dictionary<string, string>? Options(string[] args)
    {
        var d = new Dictionary<string, string>();
        for (int i = 0; i < args.Length; i++)
        {
            if (!args[i].StartsWith("--") || i + 1 >= args.Length) return null;
            d[args[i][2..]] = args[++i];
        }
        return d;
    }

    // "192.168.1.5:7455", "[fe80::1%12]:7455", "mac.local:7455": the last colon splits.
    internal static bool SplitHost(string text, out string host, out int port)
    {
        host = ""; port = 0;
        int colon = text.LastIndexOf(':');
        if (colon <= 0 || !int.TryParse(text[(colon + 1)..], out port) || port is < 1 or > 65535) return false;
        host = text[..colon].Trim('[', ']');
        return host.Length > 0;
    }

    internal static int Usage(string message)
    {
        Console.Error.WriteLine(message);
        return 2;
    }
}
