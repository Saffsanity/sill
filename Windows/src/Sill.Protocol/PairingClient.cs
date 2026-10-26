namespace Sill.Protocol;

/// <summary>
/// One pairing over TLS: a <c>sill-pair/1</c> connection, one kind 19 out, one kind 20 back
/// (Remote.swift; StreamClient+Remote.swift's <c>pair</c>). The typed code's connection takes any
/// key and its proofs bind both; the link's is pinned to the link's <c>k</c>.
/// </summary>
public static class PairingClient
{
    /// <summary>How long the Mac has to answer once the request is sent.</summary>
    public static readonly TimeSpan AnswerWait = TimeSpan.FromSeconds(15);

    public sealed record Outcome(PairingExchange.Verdict Verdict, PairResult? Result, byte[] MacFingerprint)
    {
        public bool Paired => Verdict == PairingExchange.Verdict.Paired;
    }

    /// <summary>The typed path. <paramref name="code"/> must already have passed
    /// <see cref="PairingCode.Check"/>.
    /// <paramref name="pin"/>, after an ask, holds the code's connection to the key the ask met.</summary>
    public static async Task<Outcome> PairWithCodeAsync(string host, int port, string code, DeviceIdentity identity,
        string deviceName, string? model, CancellationToken ct, byte[]? pin = null)
    {
        var (ssl, macFp) = await SillTls.ConnectAsync(host, port, SillTls.Pairing, identity, pin, ct).ConfigureAwait(false);
        await using (ssl)
            return await ExchangeAsync(ssl, PairingExchange.ForCode(code, macFp, identity.Fingerprint), macFp, deviceName, model, ct)
                .ConfigureAwait(false);
    }

    /// <summary>The link's path, to <paramref name="host"/>:<paramref name="port"/> (one of the
    /// link's addresses and its port, or an address typed beside it).</summary>
    public static async Task<Outcome> PairWithLinkAsync(string host, int port, PairLink link, DeviceIdentity identity,
        string deviceName, string? model, CancellationToken ct)
    {
        var (ssl, macFp) = await SillTls.ConnectAsync(host, port, SillTls.Pairing, identity, link.Fingerprint, ct).ConfigureAwait(false);
        await using (ssl)
            return await ExchangeAsync(ssl, PairingExchange.ForLink(link, identity.Fingerprint), macFp, deviceName, model, ct)
                .ConfigureAwait(false);
    }

    /// <summary>
    /// The home door's "pair me" (kind 19 "ask", no proof): Sill on the Mac opens its pairing window
    /// by itself and answers "shown", or says why not ("openOnMac", "locked", "busy"…). Returns the
    /// answer and the key the Mac presented, to pin the code's connection to.
    /// </summary>
    public static Task<(PairResult? Result, byte[] MacFingerprint)> AskAsync(string host, int port, DeviceIdentity identity,
        string deviceName, string? model, CancellationToken ct) =>
        ProoflessAsync(PairRequest.Ask, host, port, identity, pin: null, deviceName, model, ct);

    /// <summary>
    /// The Cancel of an ask the Mac answered "shown" (kind 19 "cancel", StreamClient+Home.swift's
    /// <c>withdrawAsk</c>): pinned to the key that answered, so the window the ask opened closes
    /// instead of staying up its 5 minutes with a live code. The answer is always "closed".
    /// </summary>
    public static Task<(PairResult? Result, byte[] MacFingerprint)> CancelAskAsync(string host, int port, DeviceIdentity identity,
        byte[] pin, string deviceName, string? model, CancellationToken ct) =>
        ProoflessAsync(PairRequest.Cancel, host, port, identity, pin, deviceName, model, ct);

    private static async Task<(PairResult? Result, byte[] MacFingerprint)> ProoflessAsync(string method, string host, int port,
        DeviceIdentity identity, byte[]? pin, string deviceName, string? model, CancellationToken ct)
    {
        var (ssl, macFp) = await SillTls.ConnectAsync(host, port, SillTls.Pairing, identity, pin, ct).ConfigureAwait(false);
        await using (ssl)
        {
            var request = new PairRequest(PairRequest.Version, method, "", deviceName, model);
            await ssl.WriteAsync(StreamHeader.Serialize(Kinds.PairRequest, 0, false,
                System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(request, SessionMessages.Json)), ct).ConfigureAwait(false);
            using var wait = CancellationTokenSource.CreateLinkedTokenSource(ct);
            wait.CancelAfter(AnswerWait);
            var m = await MessageStream.ReadAsync(ssl, StreamHeader.MaxPairingPayload, wait.Token).ConfigureAwait(false);
            if (m is not { } answer || answer.Header.Kind != Kinds.PairResult) return (null, macFp);
            return (SessionMessages.Decode<PairResult>(answer.Payload), macFp);
        }
    }

    private static async Task<Outcome> ExchangeAsync(Stream ssl, PairingExchange exchange, byte[] macFp,
        string deviceName, string? model, CancellationToken ct)
    {
        await ssl.WriteAsync(exchange.RequestMessage(deviceName, model), ct).ConfigureAwait(false);
        await ssl.FlushAsync(ct).ConfigureAwait(false);
        using var wait = CancellationTokenSource.CreateLinkedTokenSource(ct);
        wait.CancelAfter(AnswerWait);
        var message = await MessageStream.ReadAsync(ssl, StreamHeader.MaxPairingPayload, wait.Token).ConfigureAwait(false);
        if (message is not { } m || m.Header.Kind != Kinds.PairResult)
            throw new InvalidDataException(message is null ? "The Mac closed the connection without answering."
                                                           : $"The Mac answered kind {message.Value.Header.Kind}, not 20.");
        var verdict = exchange.Judge(m.Payload, out var result);
        return new Outcome(verdict, result, macFp);
    }
}
