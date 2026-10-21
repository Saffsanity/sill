using System.Text;

namespace Sill.Protocol.Tests;

/// <summary>Ticket 08's Settings panel: kinds 16 and 17, and the ledger's rules (HostSettingsLedger.swift's).</summary>
public class HostSettingsTests
{
    private static HostSettingsState State(int fps = 60, int bitrate = 15_000_000, double scale = 2, bool? direct = false, int? answering = null) =>
        new(new StreamSettings(fps, bitrate, scale, false, false, direct), true, true, null, false, null, answering, null);

    [Fact]
    public void ReadsKind16AsTheMacSendsIt()
    {
        const string json = """
            {"settings":{"maxFPS":120,"bitrate":40000000,"captureScale":2,"prioritizeSpeed":false,"virtualDisplay":true,"directWireless":false},
             "persistent":true,"virtualDisplayAvailable":true,"softwareEncoder":false,
             "stream":{"width":3840,"height":2160,"fps":60,"mbps":40,"onVirtualDisplay":false},"answering":7,
             "away":{"homeBitrate":40000000,"homeCaptureScale":2,"awayBitrate":4000000,"awayCaptureScale":1,"thisConnectionAway":false,"awayRunning":false},
             "link":{"state":"behind","withheldPerSecond":3,"bitrate":40000000}}
            """;
        var s = SessionMessages.Decode<HostSettingsState>(Encoding.UTF8.GetBytes(json))!;
        Assert.Equal(new StreamSettings(120, 40_000_000, 2, false, true, false), s.Settings);
        Assert.Equal(new RunningStream(3840, 2160, 60, 40, false), s.Stream);
        Assert.Equal(7, s.Answering);
        Assert.Equal(4_000_000, s.Away!.AwayBitrate);
        Assert.Null(s.VirtualDisplayNote);
    }

    [Fact]
    public void Kind17LeavesOutWhatDidNotChange()
    {
        var bytes = new HostSettingsChange(Token: 3, Bitrate: 40_000_000).Encode();
        Assert.Equal(17, bytes[0]);
        Assert.Equal("""{"token":3,"bitrate":40000000}""", Encoding.UTF8.GetString(bytes, 14, bytes.Length - 14));
        Assert.Equal("""{"token":4,"captureScale":1}""", Encoding.UTF8.GetString(new HostSettingsChange(Token: 4, CaptureScale: 1).Encode()[14..]));
    }

    [Fact]
    public void NothingIsSentBeforeTheFirstStateOrForWhatIsShown()
    {
        var ledger = new SettingsLedger();
        Assert.Null(ledger.Pick(new HostSettingsChange(MaxFps: 120), 1, 0));
        ledger.Receive(State(fps: 60));
        Assert.Null(ledger.Pick(new HostSettingsChange(MaxFps: 60), 2, 0));
        var sent = ledger.Pick(new HostSettingsChange(MaxFps: 120, Bitrate: 15_000_000), 3, 0);
        Assert.Equal(new HostSettingsChange(Token: 3, MaxFps: 120), sent);
        Assert.Equal(120, ledger.Displayed!.MaxFps);
        Assert.True(ledger.IsPending(SettingsLedger.Field.MaxFps));
    }

    [Fact]
    public void AnAnswerClearsItsPickAndARefusalGoesBack()
    {
        var ledger = new SettingsLedger();
        ledger.Receive(State(bitrate: 15_000_000));
        ledger.Pick(new HostSettingsChange(Bitrate: 150_000_000), 1, 0);
        // An older Mac refuses Extreme: its answer keeps 15 Mbps.
        var refused = ledger.Receive(State(bitrate: 15_000_000, answering: 1));
        Assert.Equal([SettingsLedger.Field.Bitrate], refused);
        Assert.Equal(15_000_000, ledger.Displayed!.Bitrate);
        ledger.Pick(new HostSettingsChange(Bitrate: 40_000_000), 2, 1);
        Assert.Empty(ledger.Receive(State(bitrate: 40_000_000, answering: 2)));
        Assert.False(ledger.IsPending(SettingsLedger.Field.Bitrate));
    }

    [Fact]
    public void AnOlderAnswerNeverShowsAPickTakenBack()
    {
        // 60 → 120 → 60: the answer to the first pick must not show 120.
        var ledger = new SettingsLedger();
        ledger.Receive(State(fps: 60));
        ledger.Pick(new HostSettingsChange(MaxFps: 120), 1, 0);
        ledger.Pick(new HostSettingsChange(MaxFps: 60), 2, 0.1);
        Assert.Empty(ledger.Receive(State(fps: 120, answering: 1)));
        Assert.Equal(60, ledger.Displayed!.MaxFps);
        Assert.Empty(ledger.Receive(State(fps: 60, answering: 2)));
        Assert.Equal(60, ledger.Displayed!.MaxFps);
        Assert.False(ledger.IsPending(SettingsLedger.Field.MaxFps));
    }

    [Fact]
    public void AnUnansweredPickGoesBackAfterTheTimeout()
    {
        var ledger = new SettingsLedger();
        ledger.Receive(State(scale: 2));
        ledger.Pick(new HostSettingsChange(CaptureScale: 1), 1, 0);
        Assert.False(ledger.Expire(3, 4));
        Assert.True(ledger.Expire(5, 4));
        Assert.Equal(2, ledger.Displayed!.CaptureScale);
    }

    [Fact]
    public void DirectWirelessGoesOnlyToAHostThatHasIt()
    {
        var ledger = new SettingsLedger();
        ledger.Receive(State(direct: null));
        Assert.Null(ledger.Pick(new HostSettingsChange(DirectWireless: true), 1, 0));
    }

    [Fact]
    public void QualityTitles()
    {
        Assert.Equal("Balanced — 15 Mbps", SettingsChoices.QualityTitle(15_000_000));
        Assert.Equal("Custom — 12.5 Mbps", SettingsChoices.QualityTitle(12_500_000));
    }
}
