//! Windows.Graphics.Capture: a window (by HWND) or a monitor, as BGRA textures on the stream's
//! D3D11 device. The cursor is left out (devices draw it themselves) and, where Windows allows
//! (Windows 11), so is the yellow capture border.
//!
//! Frames arrive on the frame pool's own thread (CreateFreeThreaded); the handler only keeps the
//! newest frame (an older one waiting is closed: latency beats quality) and wakes the stream's
//! thread, which does all the Direct3D work.

use std::sync::{Arc, Mutex};

use windows::core::{IInspectable, Interface};
use windows::Foundation::{TimeSpan, TypedEventHandler};
use windows::Graphics::Capture::{Direct3D11CaptureFrame, Direct3D11CaptureFramePool, GraphicsCaptureItem, GraphicsCaptureSession};
use windows::Graphics::DirectX::DirectXPixelFormat;
use windows::Graphics::SizeInt32;
use windows::Win32::Foundation::HWND;
use windows::Win32::Graphics::Direct3D11::ID3D11Texture2D;
use windows::Win32::Graphics::Gdi::HMONITOR;
use windows::Win32::System::WinRT::Direct3D11::IDirect3DDxgiInterfaceAccess;
use windows::Win32::System::WinRT::Graphics::Capture::IGraphicsCaptureItemInterop;

use super::d3d::D3d;

/// What to capture.
#[derive(Clone, Copy, Debug)]
pub enum Target {
    Window(HWND),
    Monitor(HMONITOR),
}

unsafe impl Send for Target {}

/// Buffers in the frame pool: one being converted, one waiting, one for the next frame.
const BUFFERS: i32 = 3;

pub struct Capture {
    pool: Direct3D11CaptureFramePool,
    session: GraphicsCaptureSession,
    item: GraphicsCaptureItem,
    pending: Arc<Mutex<Option<Direct3D11CaptureFrame>>>,
    frame_token: i64,
    closed_token: i64,
    pool_size: SizeInt32,
}

impl Capture {
    /// Starts capturing. `on_frame` runs (on the pool's thread) whenever a new frame waits;
    /// `on_closed` when the window closes or the monitor goes.
    pub fn start(
        d3d: &D3d,
        target: Target,
        fps: u32,
        on_frame: Arc<dyn Fn() + Send + Sync>,
        on_closed: Arc<dyn Fn() + Send + Sync>,
    ) -> windows::core::Result<Self> {
        if !GraphicsCaptureSession::IsSupported().unwrap_or(false) {
            return Err(windows::core::Error::new(
                windows::Win32::Foundation::E_NOTIMPL,
                "Windows.Graphics.Capture is not supported here (Windows 10 1903 or later is needed)",
            ));
        }
        let interop = windows::core::factory::<GraphicsCaptureItem, IGraphicsCaptureItemInterop>()?;
        let item: GraphicsCaptureItem = unsafe {
            match target {
                Target::Window(hwnd) => interop.CreateForWindow(hwnd)?,
                Target::Monitor(monitor) => interop.CreateForMonitor(monitor)?,
            }
        };
        let size = item.Size()?;
        let pool = Direct3D11CaptureFramePool::CreateFreeThreaded(
            &d3d.winrt,
            DirectXPixelFormat::B8G8R8A8UIntNormalized,
            BUFFERS,
            size,
        )?;
        let session = pool.CreateCaptureSession(&item)?;
        // Windows 10 2004 and later; the border needs Windows 11. Older systems keep their defaults.
        let _ = session.SetIsCursorCaptureEnabled(false);
        let _ = session.SetIsBorderRequired(false);
        // Windows 11 24H2: no more frames than the stream wants.
        let _ = session.SetMinUpdateInterval(TimeSpan { Duration: 10_000_000 / fps.max(1) as i64 });

        let pending: Arc<Mutex<Option<Direct3D11CaptureFrame>>> = Arc::new(Mutex::new(None));
        let slot = pending.clone();
        let frame_token = pool.FrameArrived(&TypedEventHandler::<Direct3D11CaptureFramePool, IInspectable>::new(
            move |pool, _| {
                if let Some(pool) = pool.as_ref() {
                    while let Ok(frame) = pool.TryGetNextFrame() {
                        let older = slot.lock().ok().and_then(|mut s| s.replace(frame));
                        if let Some(older) = older {
                            let _ = older.Close();
                        }
                    }
                    on_frame();
                }
                Ok(())
            },
        ))?;
        let closed_token = item.Closed(&TypedEventHandler::<GraphicsCaptureItem, IInspectable>::new(move |_, _| {
            on_closed();
            Ok(())
        }))?;
        session.StartCapture()?;
        Ok(Capture { pool, session, item, pending, frame_token, closed_token, pool_size: size })
    }

    /// The newest frame waiting, if any.
    pub fn take(&self) -> Option<Direct3D11CaptureFrame> {
        self.pending.lock().ok().and_then(|mut s| s.take())
    }

    /// The pool's buffers follow the content: a window that grew needs bigger buffers (WGC then
    /// delivers the next frames at the new size).
    pub fn fit_pool(&mut self, d3d: &D3d, content: SizeInt32) -> windows::core::Result<()> {
        if content.Width == self.pool_size.Width && content.Height == self.pool_size.Height {
            return Ok(());
        }
        if content.Width <= 0 || content.Height <= 0 {
            return Ok(());
        }
        self.pool.Recreate(&d3d.winrt, DirectXPixelFormat::B8G8R8A8UIntNormalized, BUFFERS, content)?;
        self.pool_size = content;
        Ok(())
    }

    /// The capture item's current size (the window's or monitor's).
    pub fn item_size(&self) -> Option<SizeInt32> {
        self.item.Size().ok()
    }
}

impl Drop for Capture {
    fn drop(&mut self) {
        let _ = self.pool.RemoveFrameArrived(self.frame_token);
        let _ = self.item.RemoveClosed(self.closed_token);
        if let Some(frame) = self.take() {
            let _ = frame.Close();
        }
        let _ = self.session.Close();
        let _ = self.pool.Close();
    }
}

/// A captured frame's texture.
pub fn frame_texture(frame: &Direct3D11CaptureFrame) -> windows::core::Result<ID3D11Texture2D> {
    let surface = frame.Surface()?;
    let access: IDirect3DDxgiInterfaceAccess = surface.cast()?;
    unsafe { access.GetInterface() }
}
