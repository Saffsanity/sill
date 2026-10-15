//! The Direct3D 11 device a stream runs on: Windows.Graphics.Capture delivers its frames there,
//! the video processor turns them into NV12 there, and a hardware encoder reads them there. It is
//! made on the adapter the encoder belongs to (a laptop's GPUs each have their own), with video
//! support, BGRA support (capture), and multithread protection (Media Foundation's encoder
//! threads use it too).

use windows::core::Interface;
use windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
use windows::Win32::Foundation::{HMODULE, LUID};
use windows::Win32::Graphics::Direct3D::{
    D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_UNKNOWN, D3D_FEATURE_LEVEL_10_0, D3D_FEATURE_LEVEL_10_1,
    D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_11_1,
};
use windows::Win32::Graphics::Direct3D11::{
    D3D11CreateDevice, ID3D11Device, ID3D11DeviceContext, ID3D11Multithread, ID3D11Texture2D,
    D3D11_BIND_RENDER_TARGET, D3D11_BIND_SHADER_RESOURCE, D3D11_BIND_VIDEO_ENCODER, D3D11_CPU_ACCESS_READ, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
    D3D11_CREATE_DEVICE_VIDEO_SUPPORT, D3D11_SDK_VERSION, D3D11_TEXTURE2D_DESC, D3D11_USAGE_DEFAULT,
    D3D11_USAGE_STAGING,
};
use windows::Win32::Graphics::Dxgi::Common::{DXGI_FORMAT, DXGI_FORMAT_NV12, DXGI_SAMPLE_DESC};
use windows::Win32::Graphics::Dxgi::{CreateDXGIFactory1, IDXGIAdapter, IDXGIDevice, IDXGIFactory1, IDXGIFactory4};
use windows::Win32::Media::MediaFoundation::{IMFDXGIDeviceManager, MFCreateDXGIDeviceManager};
use windows::Win32::System::WinRT::Direct3D11::CreateDirect3D11DeviceFromDXGIDevice;

pub struct D3d {
    pub device: ID3D11Device,
    pub context: ID3D11DeviceContext,
    /// The same device for WinRT (the capture frame pool).
    pub winrt: IDirect3DDevice,
    /// The same device for Media Foundation (a D3D-aware encoder).
    pub manager: IMFDXGIDeviceManager,
    /// The adapter it was made on.
    pub adapter: LUID,
}

impl D3d {
    /// A device on the adapter with this LUID, or on the default adapter.
    pub fn new(adapter: Option<LUID>) -> windows::core::Result<Self> {
        unsafe {
            let adapter: Option<IDXGIAdapter> = match adapter {
                Some(luid) => {
                    let factory: IDXGIFactory1 = CreateDXGIFactory1()?;
                    factory.cast::<IDXGIFactory4>().ok().and_then(|f| f.EnumAdapterByLuid(luid).ok())
                }
                None => None,
            };
            let driver = if adapter.is_some() { D3D_DRIVER_TYPE_UNKNOWN } else { D3D_DRIVER_TYPE_HARDWARE };
            let levels = [D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0];
            let mut device = None;
            let mut context = None;
            D3D11CreateDevice(
                adapter.as_ref(),
                driver,
                HMODULE::default(),
                D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
                Some(&levels),
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                Some(&mut context),
            )?;
            let device = device.ok_or_else(windows::core::Error::empty)?;
            let context = context.ok_or_else(windows::core::Error::empty)?;
            if let Ok(mt) = context.cast::<ID3D11Multithread>() {
                let _ = mt.SetMultithreadProtected(true);
            }
            let dxgi: IDXGIDevice = device.cast()?;
            let adapter = dxgi.GetAdapter().and_then(|a| a.GetDesc()).map(|d| d.AdapterLuid).unwrap_or_default();
            let winrt: IDirect3DDevice = CreateDirect3D11DeviceFromDXGIDevice(&dxgi)?.cast()?;
            let mut token = 0u32;
            let mut manager = None;
            MFCreateDXGIDeviceManager(&mut token, &mut manager)?;
            let manager = manager.ok_or_else(windows::core::Error::empty)?;
            manager.ResetDevice(&device, token)?;
            Ok(D3d { device, context, winrt, manager, adapter })
        }
    }

    /// A GPU texture the video processor can write (NV12, also marked for the video encoder
    /// where the driver allows it) or read (BGRA).
    pub fn texture(&self, width: u32, height: u32, format: DXGI_FORMAT) -> windows::core::Result<ID3D11Texture2D> {
        if format == DXGI_FORMAT_NV12 {
            let encoder = (D3D11_BIND_RENDER_TARGET.0 | D3D11_BIND_VIDEO_ENCODER.0) as u32;
            if let Ok(t) = self.texture_bound(width, height, format, encoder) {
                return Ok(t);
            }
            return self.texture_bound(width, height, format, D3D11_BIND_RENDER_TARGET.0 as u32);
        }
        let bind = (D3D11_BIND_RENDER_TARGET.0 | D3D11_BIND_SHADER_RESOURCE.0) as u32;
        self.texture_bound(width, height, format, bind)
    }

    fn texture_bound(&self, width: u32, height: u32, format: DXGI_FORMAT, bind: u32) -> windows::core::Result<ID3D11Texture2D> {
        let desc = D3D11_TEXTURE2D_DESC {
            Width: width,
            Height: height,
            MipLevels: 1,
            ArraySize: 1,
            Format: format,
            SampleDesc: DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
            Usage: D3D11_USAGE_DEFAULT,
            BindFlags: bind,
            CPUAccessFlags: 0,
            MiscFlags: 0,
        };
        let mut tex = None;
        unsafe { self.device.CreateTexture2D(&desc, None, Some(&mut tex))? };
        tex.ok_or_else(windows::core::Error::empty)
    }

    /// An NV12 texture the CPU can read (a software encoder's input goes through it).
    pub fn staging_nv12(&self, width: u32, height: u32) -> windows::core::Result<ID3D11Texture2D> {
        let desc = D3D11_TEXTURE2D_DESC {
            Width: width,
            Height: height,
            MipLevels: 1,
            ArraySize: 1,
            Format: DXGI_FORMAT_NV12,
            SampleDesc: DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
            Usage: D3D11_USAGE_STAGING,
            BindFlags: 0,
            CPUAccessFlags: D3D11_CPU_ACCESS_READ.0 as u32,
            MiscFlags: 0,
        };
        let mut tex = None;
        unsafe { self.device.CreateTexture2D(&desc, None, Some(&mut tex))? };
        tex.ok_or_else(windows::core::Error::empty)
    }
}
