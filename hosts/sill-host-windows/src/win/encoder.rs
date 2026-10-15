//! HEVC through Media Foundation: the GPU vendor's hardware encoder MFT first (NVIDIA NVENC,
//! AMD AMF/VCN, Intel Quick Sync, each registered as an asynchronous MFT), Microsoft's software
//! encoder from the HEVC Video Extensions after that.
//!
//! Tuned as the Mac's VideoToolbox session is: real time and low latency
//! (CODECAPI_AVLowLatencyMode), no B-frames, constant bit rate at the stream's bitrate, a long
//! GOP (4 s, a safety interval) with keyframes on request (CODECAPI_AVEncVideoForceKeyFrame).
//! One frame inside the encoder at a time, as on the Mac ("The 33 fps plateau"), unless an
//! encoder shows it needs more before it returns anything; a frame with no room waits in the
//! stream's one-slot mailbox, where a newer one replaces it.
//!
//! An asynchronous MFT talks through events (METransformNeedInput, METransformHaveOutput), read
//! by a thread of its own that blocks on GetEvent; the stream's thread only calls ProcessInput.
//! A synchronous MFT (the software encoder) is driven entirely from the stream's thread.

use std::collections::VecDeque;
use std::mem::ManuallyDrop;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use sill_host_core::platform::EncodedFrame;
use windows::core::{Interface, GUID, PWSTR};
use windows::Win32::Foundation::{LUID, VARIANT_BOOL};
use windows::Win32::Graphics::Direct3D11::ID3D11Texture2D;
use windows::Win32::Media::MediaFoundation::*;
use windows::Win32::System::Com::CoTaskMemFree;
use windows::Win32::System::Variant::{VARIANT, VT_BOOL, VT_UI4};

use super::d3d::D3d;
use super::util::{com_init, log, Shared};
use crate::annexb::AccessUnits;

/// How a stream wants its encoder.
#[derive(Clone, Copy, Debug)]
pub struct Settings {
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub bitrate: u32,
    pub prioritize_speed: bool,
}

/// An HEVC encoder Media Foundation lists, not yet made.
pub struct Candidate {
    activate: Shared<IMFActivate>,
    pub name: String,
    pub hardware: bool,
    /// The adapter a hardware encoder belongs to: the stream's device must be made there.
    pub adapter: Option<LUID>,
}

/// Starts Media Foundation once for the process.
pub fn startup() -> Result<(), String> {
    static STARTED: OnceLock<Result<(), String>> = OnceLock::new();
    STARTED
        .get_or_init(|| unsafe {
            com_init();
            MFStartup(MF_VERSION, MFSTARTUP_LITE).map_err(|e| format!("Media Foundation did not start: {e}"))
        })
        .clone()
}

/// Every HEVC encoder that takes NV12, hardware first (in Media Foundation's preferred order),
/// then software.
pub fn candidates() -> Vec<Candidate> {
    if startup().is_err() {
        return Vec::new();
    }
    let mut out = enumerate(MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER, true);
    out.extend(enumerate(MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_SORTANDFILTER, false));
    out
}

/// Why there is no HEVC encoder, in the person's words.
pub const NO_ENCODER: &str = "No HEVC encoder: Media Foundation lists no hardware HEVC encoder on this PC's \
GPU and no software one. Install the \"HEVC Video Extensions\" from the Microsoft Store (or update the GPU \
driver: NVIDIA GTX 950 and later, AMD RX 400 and later, Intel 6th generation and later encode HEVC).";

fn enumerate(flags: MFT_ENUM_FLAG, hardware: bool) -> Vec<Candidate> {
    let input = MFT_REGISTER_TYPE_INFO { guidMajorType: MFMediaType_Video, guidSubtype: MFVideoFormat_NV12 };
    let output = MFT_REGISTER_TYPE_INFO { guidMajorType: MFMediaType_Video, guidSubtype: MFVideoFormat_HEVC };
    let mut list: *mut Option<IMFActivate> = std::ptr::null_mut();
    let mut count = 0u32;
    let mut out = Vec::new();
    unsafe {
        let hardware_input = if hardware { None } else { Some(&input as *const _) };
        if MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, flags, hardware_input, Some(&output), &mut list, &mut count).is_err() {
            return out;
        }
        for i in 0..count as usize {
            // Each element is ours to release; reading it takes the reference.
            let Some(activate) = std::ptr::read(list.add(i)) else { continue };
            let name = attribute_string(&activate, &MFT_FRIENDLY_NAME_Attribute).unwrap_or_else(|| "HEVC encoder".into());
            let adapter = luid(&activate);
            out.push(Candidate { activate: Shared(activate), name, hardware, adapter });
        }
        if !list.is_null() {
            CoTaskMemFree(Some(list as *const _));
        }
    }
    out
}

fn attribute_string(attrs: &IMFAttributes, key: &GUID) -> Option<String> {
    unsafe {
        let mut p = PWSTR::null();
        let mut len = 0u32;
        attrs.GetAllocatedString(key, &mut p, &mut len).ok()?;
        let s = p.to_string().ok();
        CoTaskMemFree(Some(p.0 as *const _));
        s
    }
}

fn luid(attrs: &IMFAttributes) -> Option<LUID> {
    let mut buf = [0u8; 8];
    unsafe { attrs.GetBlob(&MFT_ENUM_ADAPTER_LUID, &mut buf, None).ok()? };
    Some(LUID {
        LowPart: u32::from_le_bytes([buf[0], buf[1], buf[2], buf[3]]),
        HighPart: i32::from_le_bytes([buf[4], buf[5], buf[6], buf[7]]),
    })
}

/// Since the encoder last made progress (an output, or the oldest frame inside going in), while
/// something is inside.
fn stalled_for(st: &State) -> Option<Duration> {
    let (_, went_in) = st.in_flight.front()?;
    Some(went_in.elapsed().min(st.last_output.elapsed()))
}

struct State {
    need_input: u32,
    /// Each frame inside: its sample time and when it went in.
    in_flight: VecDeque<(i64, Instant)>,
    /// When the encoder last returned something (or the stream began).
    last_output: Instant,
    /// How many frames may be inside at once: 1, raised only for an encoder that returns nothing
    /// until it holds more.
    max_in_flight: usize,
    au: AccessUnits,
    error: Option<String>,
    provides_samples: bool,
    out_buffer_size: u32,
    /// Our output sample for an encoder that wants one from us, reused while ProcessOutput gives
    /// nothing back (a 4K frame's buffer is 12 MB).
    spare_output: Option<Shared<IMFSample>>,
}

struct Inner {
    mft: Shared<IMFTransform>,
    codec: Option<Shared<ICodecAPI>>,
    events: Option<Shared<IMFMediaEventGenerator>>,
    state: Mutex<State>,
    stopping: AtomicBool,
    settings: Settings,
    deliver: Box<dyn Fn(EncodedFrame) + Send + Sync>,
    wake: Arc<dyn Fn() + Send + Sync>,
}

pub struct Encoder {
    inner: Arc<Inner>,
    event_thread: Option<JoinHandle<()>>,
    pub name: String,
    pub hardware: bool,
    /// Whether it reads GPU textures (else frames are copied to memory for it).
    pub d3d_aware: bool,
}

impl Encoder {
    /// Makes and configures `candidate`. `deliver` gets each encoded frame (on the event thread
    /// for an asynchronous encoder); `wake` is called when the encoder wants input or failed.
    pub fn new(
        candidate: &Candidate,
        d3d: &D3d,
        settings: Settings,
        deliver: Box<dyn Fn(EncodedFrame) + Send + Sync>,
        wake: Arc<dyn Fn() + Send + Sync>,
    ) -> Result<Encoder, String> {
        startup()?;
        let fail = |what: &str, e: windows::core::Error| format!("{} ({}): {what}: {e}", candidate.name, kind(candidate));
        unsafe {
            let mft: IMFTransform = candidate.activate.ActivateObject().map_err(|e| fail("activate", e))?;
            // The activation object caches what it made: detached, the next ActivateObject (a new
            // size, a retry) makes a fresh MFT instead of returning this one after its shutdown.
            let _ = candidate.activate.DetachObject();
            let attrs = mft.GetAttributes().ok();
            let is_async = attrs.as_ref().and_then(|a| a.GetUINT32(&MF_TRANSFORM_ASYNC).ok()).unwrap_or(0) != 0;
            if is_async {
                if let Some(a) = &attrs {
                    a.SetUINT32(&MF_TRANSFORM_ASYNC_UNLOCK, 1).map_err(|e| fail("unlock async", e))?;
                }
            }
            let d3d_aware = attrs.as_ref().and_then(|a| a.GetUINT32(&MF_SA_D3D11_AWARE).ok()).unwrap_or(0) != 0;
            if d3d_aware {
                mft.ProcessMessage(MFT_MESSAGE_SET_D3D_MANAGER, d3d.manager.as_raw() as usize)
                    .map_err(|e| fail("set the D3D manager", e))?;
            }
            let codec: Option<ICodecAPI> = mft.cast().ok();
            if let Some(c) = &codec {
                configure(c, &settings);
            }
            set_types(&mft, &settings).map_err(|e| fail("set the media types", e))?;
            if let Some(c) = &codec {
                configure(c, &settings); // some encoders take rate control only once the types are set
            }
            let info = mft.GetOutputStreamInfo(0).map_err(|e| fail("output stream info", e))?;
            let provides = info.dwFlags
                & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES.0 as u32 | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES.0 as u32)
                != 0;
            let mut au = AccessUnits::new();
            if let Some(header) = sequence_header(&mft) {
                au.set_sequence_header(&header);
            }
            mft.ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0).map_err(|e| fail("begin streaming", e))?;
            mft.ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0).map_err(|e| fail("start of stream", e))?;
            let events: Option<IMFMediaEventGenerator> = if is_async { mft.cast().ok() } else { None };
            if is_async && events.is_none() {
                return Err(format!("{}: an asynchronous encoder without events", candidate.name));
            }
            let inner = Arc::new(Inner {
                mft: Shared(mft),
                codec: codec.map(Shared),
                events: events.map(Shared),
                state: Mutex::new(State {
                    need_input: 0,
                    in_flight: VecDeque::new(),
                    last_output: Instant::now(),
                    max_in_flight: 1,
                    au,
                    error: None,
                    provides_samples: provides,
                    out_buffer_size: info.cbSize.max(settings.width * settings.height * 3 / 2).max(1 << 20),
                    spare_output: None,
                }),
                stopping: AtomicBool::new(false),
                settings,
                deliver,
                wake,
            });
            let event_thread = if is_async {
                let inner = inner.clone();
                Some(
                    std::thread::Builder::new()
                        .name("sill-encoder-events".into())
                        .spawn(move || event_loop(inner))
                        .map_err(|e| format!("encoder thread: {e}"))?,
                )
            } else {
                None
            };
            Ok(Encoder { inner, event_thread, name: candidate.name.clone(), hardware: candidate.hardware, d3d_aware })
        }
    }

    /// Whether a frame may go in now.
    pub fn accepts(&self) -> bool {
        let Ok(mut st) = self.inner.state.lock() else { return false };
        if st.error.is_some() {
            return false;
        }
        if self.inner.events.is_some() && st.need_input == 0 {
            return false;
        }
        if st.in_flight.len() < st.max_in_flight {
            return true;
        }
        // Nothing came back from a full encoder for 50 ms: it may need more frames before its
        // first output. Let one more in, from now on.
        let stalled = stalled_for(&st).is_some_and(|d| d > Duration::from_millis(50));
        if stalled && st.max_in_flight < 4 {
            st.max_in_flight += 1;
            log(&format!("Encoder: allowing {} frames inside (it returned nothing with fewer)", st.max_in_flight));
            return true;
        }
        false
    }

    /// How long frames have been inside with nothing coming back (None when none is inside): the
    /// hang watchdog, and the still source's nudge for an encoder that holds a frame.
    pub fn stalled_for(&self) -> Option<Duration> {
        stalled_for(&*self.inner.state.lock().ok()?)
    }

    /// `stalled_for`, but only while the encoder is full (as many frames inside as it may hold):
    /// an encoder that keeps one frame back with room for more is not hung.
    pub fn hung_for(&self) -> Option<Duration> {
        let st = self.inner.state.lock().ok()?;
        if st.in_flight.len() < st.max_in_flight {
            return None;
        }
        stalled_for(&st)
    }

    pub fn error(&self) -> Option<String> {
        self.inner.state.lock().ok()?.error.clone()
    }

    /// Encodes one NV12 frame (a GPU texture for a D3D-aware encoder, else its bytes), at
    /// `time` (100 ns units), a keyframe if `keyframe`.
    pub fn submit(&self, input: Input, time: i64, keyframe: bool) -> Result<(), String> {
        let inner = &self.inner;
        let duration = 10_000_000 / inner.settings.fps.max(1) as i64;
        unsafe {
            let sample = match input {
                Input::Texture(tex) => texture_sample(&tex),
                Input::Bytes(bytes) => memory_sample(&bytes),
            }
            .map_err(|e| format!("input sample: {e}"))?;
            let _ = sample.SetSampleTime(time);
            let _ = sample.SetSampleDuration(duration);
            if keyframe {
                if let Some(c) = &inner.codec {
                    let _ = c.SetValue(&CODECAPI_AVEncVideoForceKeyFrame, &variant_u32(1));
                }
            }
            let mut ready = Vec::new();
            {
                let mut st = inner.state.lock().map_err(|_| "encoder state poisoned".to_string())?;
                let mut result = inner.mft.ProcessInput(0, &sample, 0);
                if inner.events.is_none() && matches!(&result, Err(e) if e.code() == MF_E_NOTACCEPTING) {
                    drain_sync(inner, &mut st, &mut ready)?;
                    result = inner.mft.ProcessInput(0, &sample, 0);
                }
                result.map_err(|e| format!("ProcessInput: {e}"))?;
                st.in_flight.push_back((time, Instant::now()));
                if inner.events.is_some() {
                    st.need_input = st.need_input.saturating_sub(1);
                } else {
                    drain_sync(inner, &mut st, &mut ready)?;
                }
            }
            for frame in ready {
                (inner.deliver)(frame);
            }
        }
        Ok(())
    }
}

impl Drop for Encoder {
    fn drop(&mut self) {
        let inner = &self.inner;
        inner.stopping.store(true, Ordering::SeqCst);
        unsafe {
            let _ = inner.mft.ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
            let _ = inner.mft.ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
            // An asynchronous MFT's GetEvent returns MF_E_SHUTDOWN once it is shut down.
            match inner.mft.cast::<IMFShutdown>() {
                Ok(shutdown) => {
                    let _ = shutdown.Shutdown();
                }
                Err(_) => {
                    let _ = inner.mft.ProcessMessage(MFT_MESSAGE_COMMAND_DRAIN, 0);
                }
            }
        }
        if let Some(thread) = self.event_thread.take() {
            let deadline = Instant::now() + Duration::from_secs(1);
            while !thread.is_finished() && Instant::now() < deadline {
                std::thread::sleep(Duration::from_millis(5));
            }
            if thread.is_finished() {
                let _ = thread.join();
            } else {
                log("Encoder: its event thread did not end within 1 s; left behind");
            }
        }
    }
}

/// A frame for the encoder.
pub enum Input {
    Texture(ID3D11Texture2D),
    Bytes(Vec<u8>),
}

unsafe fn texture_sample(tex: &ID3D11Texture2D) -> windows::core::Result<IMFSample> {
    unsafe {
        let buffer = MFCreateDXGISurfaceBuffer(&ID3D11Texture2D::IID, tex, 0, false)?;
        if let Ok(b2d) = buffer.cast::<IMF2DBuffer>() {
            if let Ok(len) = b2d.GetContiguousLength() {
                let _ = buffer.SetCurrentLength(len);
            }
        }
        let sample = MFCreateSample()?;
        sample.AddBuffer(&buffer)?;
        Ok(sample)
    }
}

unsafe fn memory_sample(bytes: &[u8]) -> windows::core::Result<IMFSample> {
    unsafe {
        let buffer = MFCreateMemoryBuffer(bytes.len() as u32)?;
        let mut ptr = std::ptr::null_mut();
        buffer.Lock(&mut ptr, None, None)?;
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr, bytes.len());
        buffer.Unlock()?;
        buffer.SetCurrentLength(bytes.len() as u32)?;
        let sample = MFCreateSample()?;
        sample.AddBuffer(&buffer)?;
        Ok(sample)
    }
}

fn kind(c: &Candidate) -> &'static str {
    if c.hardware {
        "hardware"
    } else {
        "software"
    }
}

fn variant_u32(v: u32) -> VARIANT {
    let mut var = VARIANT::default();
    unsafe {
        let inner = &mut *var.Anonymous.Anonymous;
        inner.vt = VT_UI4;
        inner.Anonymous.ulVal = v;
    }
    var
}

fn variant_bool(v: bool) -> VARIANT {
    let mut var = VARIANT::default();
    unsafe {
        let inner = &mut *var.Anonymous.Anonymous;
        inner.vt = VT_BOOL;
        inner.Anonymous.boolVal = VARIANT_BOOL(if v { -1 } else { 0 });
    }
    var
}

/// The encoder's knobs. Each is optional to an encoder: one it does not take is skipped.
fn configure(codec: &ICodecAPI, s: &Settings) {
    unsafe {
        let _ = codec.SetValue(&CODECAPI_AVLowLatencyMode, &variant_bool(true));
        let _ = codec.SetValue(&CODECAPI_AVEncCommonRateControlMode, &variant_u32(eAVEncCommonRateControlMode_CBR.0 as u32));
        let _ = codec.SetValue(&CODECAPI_AVEncCommonMeanBitRate, &variant_u32(s.bitrate));
        // A one-second buffer, as the Mac's DataRateLimits.
        let _ = codec.SetValue(&CODECAPI_AVEncCommonBufferSize, &variant_u32(s.bitrate));
        let _ = codec.SetValue(&CODECAPI_AVEncMPVDefaultBPictureCount, &variant_u32(0));
        // Keyframes come on request; this is only a safety interval (the Mac's 4 s).
        let _ = codec.SetValue(&CODECAPI_AVEncMPVGOPSize, &variant_u32(s.fps.max(1) * 4));
        let _ = codec.SetValue(&CODECAPI_AVEncCommonQualityVsSpeed, &variant_u32(if s.prioritize_speed { 0 } else { 50 }));
    }
}

fn set_color(t: &IMFMediaType) {
    unsafe {
        let _ = t.SetUINT32(&MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235.0 as u32);
        let _ = t.SetUINT32(&MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709.0 as u32);
        let _ = t.SetUINT32(&MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT709.0 as u32);
        let _ = t.SetUINT32(&MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_709.0 as u32);
    }
}

fn set_shape(t: &IMFMediaType, s: &Settings) -> windows::core::Result<()> {
    unsafe {
        t.SetUINT64(&MF_MT_FRAME_SIZE, ((s.width as u64) << 32) | s.height as u64)?;
        t.SetUINT64(&MF_MT_FRAME_RATE, ((s.fps.max(1) as u64) << 32) | 1)?;
        t.SetUINT64(&MF_MT_PIXEL_ASPECT_RATIO, (1u64 << 32) | 1)?;
        t.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32)?;
    }
    set_color(t);
    Ok(())
}

/// The output type (HEVC Main at the stream's size, rate and bitrate), then the input (NV12).
fn set_types(mft: &IMFTransform, s: &Settings) -> windows::core::Result<()> {
    unsafe {
        let out = MFCreateMediaType()?;
        out.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
        out.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_HEVC)?;
        out.SetUINT32(&MF_MT_AVG_BITRATE, s.bitrate)?;
        out.SetUINT32(&MF_MT_MPEG2_PROFILE, eAVEncH265VProfile_Main_420_8.0 as u32)?;
        set_shape(&out, s)?;
        mft.SetOutputType(0, &out, 0)?;

        // The encoder's own NV12 type when it lists one (it may carry attributes it wants).
        let mut index = 0;
        while let Ok(t) = mft.GetInputAvailableType(0, index) {
            index += 1;
            if t.GetGUID(&MF_MT_SUBTYPE).ok() != Some(MFVideoFormat_NV12) {
                continue;
            }
            set_shape(&t, s)?;
            let _ = t.SetUINT32(&MF_MT_DEFAULT_STRIDE, s.width);
            if mft.SetInputType(0, &t, 0).is_ok() {
                return Ok(());
            }
        }
        let input = MFCreateMediaType()?;
        input.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
        input.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_NV12)?;
        set_shape(&input, s)?;
        let _ = input.SetUINT32(&MF_MT_DEFAULT_STRIDE, s.width);
        mft.SetInputType(0, &input, 0)
    }
}

fn sequence_header(mft: &IMFTransform) -> Option<Vec<u8>> {
    unsafe {
        let t = mft.GetOutputCurrentType(0).ok()?;
        let size = t.GetBlobSize(&MF_MT_MPEG_SEQUENCE_HEADER).ok()?;
        if size == 0 {
            return None;
        }
        let mut buf = vec![0u8; size as usize];
        t.GetBlob(&MF_MT_MPEG_SEQUENCE_HEADER, &mut buf, None).ok()?;
        Some(buf)
    }
}

/// The asynchronous encoder's events, until it is shut down or fails.
fn event_loop(inner: Arc<Inner>) {
    com_init();
    let Some(events) = inner.events.as_ref() else { return };
    loop {
        if inner.stopping.load(Ordering::SeqCst) {
            break;
        }
        let event = unsafe { events.GetEvent(MEDIA_EVENT_GENERATOR_GET_EVENT_FLAGS(0)) };
        let event = match event {
            Ok(e) => e,
            Err(e) => {
                if !inner.stopping.load(Ordering::SeqCst) {
                    fail(&inner, format!("GetEvent: {e}"));
                }
                break;
            }
        };
        let kind = unsafe { event.GetType().unwrap_or(0) } as i32;
        if kind == METransformNeedInput.0 {
            if let Ok(mut st) = inner.state.lock() {
                st.need_input += 1;
            }
            (inner.wake)();
        } else if kind == METransformHaveOutput.0 {
            let mut ready = Vec::new();
            let result = match inner.state.lock() {
                Ok(mut st) => output_once(&inner, &mut st, &mut ready).map(|_| ()),
                Err(_) => Err("encoder state poisoned".into()),
            };
            for frame in ready {
                (inner.deliver)(frame);
            }
            if let Err(e) = result {
                fail(&inner, e);
                break;
            }
            (inner.wake)();
        } else if kind == METransformDrainComplete.0 {
            if inner.stopping.load(Ordering::SeqCst) {
                break;
            }
        } else if kind == MEError.0 {
            let status = unsafe { event.GetStatus().map(|s| s.0).unwrap_or(0) };
            fail(&inner, format!("the encoder reported an error ({status:#010x})"));
            break;
        }
    }
}

fn fail(inner: &Inner, message: String) {
    if let Ok(mut st) = inner.state.lock() {
        if st.error.is_none() {
            st.error = Some(message);
        }
    }
    (inner.wake)();
}

/// A synchronous encoder: every output it has.
fn drain_sync(inner: &Inner, st: &mut State, ready: &mut Vec<EncodedFrame>) -> Result<(), String> {
    for _ in 0..16 {
        if !output_once(inner, st, ready)? {
            break;
        }
    }
    Ok(())
}

/// One ProcessOutput. True when it produced something (or changed its type: call again).
fn output_once(inner: &Inner, st: &mut State, ready: &mut Vec<EncodedFrame>) -> Result<bool, String> {
    unsafe {
        let ours = if st.provides_samples {
            None
        } else if let Some(spare) = st.spare_output.take() {
            Some(spare.0)
        } else {
            let buffer = MFCreateMemoryBuffer(st.out_buffer_size).map_err(|e| format!("output buffer: {e}"))?;
            let sample = MFCreateSample().map_err(|e| format!("output sample: {e}"))?;
            sample.AddBuffer(&buffer).map_err(|e| format!("output sample: {e}"))?;
            Some(sample)
        };
        let mut buffers = [MFT_OUTPUT_DATA_BUFFER {
            dwStreamID: 0,
            pSample: ManuallyDrop::new(ours),
            dwStatus: 0,
            pEvents: ManuallyDrop::new(None),
        }];
        let mut status = 0u32;
        let result = inner.mft.ProcessOutput(0, &mut buffers, &mut status);
        let sample = ManuallyDrop::take(&mut buffers[0].pSample);
        drop(ManuallyDrop::take(&mut buffers[0].pEvents));
        match result {
            Ok(()) => {}
            Err(e) if e.code() == MF_E_TRANSFORM_NEED_MORE_INPUT => {
                if !st.provides_samples {
                    st.spare_output = sample.map(Shared);
                }
                return Ok(false);
            }
            Err(e) if e.code() == MF_E_TRANSFORM_STREAM_CHANGE => {
                let t = inner.mft.GetOutputAvailableType(0, 0).map_err(|e| format!("stream change: {e}"))?;
                inner.mft.SetOutputType(0, &t, 0).map_err(|e| format!("stream change: {e}"))?;
                if let Some(header) = sequence_header(&inner.mft) {
                    st.au.set_sequence_header(&header);
                }
                if let Ok(info) = inner.mft.GetOutputStreamInfo(0) {
                    st.out_buffer_size = info.cbSize.max(st.out_buffer_size);
                }
                return Ok(true);
            }
            Err(e) => return Err(format!("ProcessOutput: {e}")),
        }
        let Some(sample) = sample else { return Ok(true) };
        let clean = sample.GetUINT32(&MFSampleExtension_CleanPoint).unwrap_or(0) != 0;
        let buffer = sample.ConvertToContiguousBuffer().map_err(|e| format!("output buffer: {e}"))?;
        let mut ptr = std::ptr::null_mut();
        let mut len = 0u32;
        buffer.Lock(&mut ptr, None, Some(&mut len)).map_err(|e| format!("output lock: {e}"))?;
        let bytes = std::slice::from_raw_parts(ptr, len as usize).to_vec();
        let _ = buffer.Unlock();
        // Every frame up to this one's time is done (one an encoder dropped included).
        st.last_output = Instant::now();
        match sample.GetSampleTime() {
            Ok(t) if st.in_flight.front().is_some_and(|(f, _)| *f <= t) => {
                while st.in_flight.front().is_some_and(|(f, _)| *f <= t) {
                    st.in_flight.pop_front();
                }
            }
            _ => {
                st.in_flight.pop_front();
            }
        }
        if st.au.parameter_sets().is_none() {
            if let Some(header) = sequence_header(&inner.mft) {
                st.au.set_sequence_header(&header);
            }
        }
        if let Some(frame) = st.au.frame(&bytes, clean, inner.settings.width, inner.settings.height) {
            ready.push(frame);
        }
        Ok(true)
    }
}
