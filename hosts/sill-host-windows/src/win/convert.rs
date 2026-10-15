//! BGRA frames as the encoder's NV12, on the GPU: the D3D11 video processor converts (BT.709,
//! video range, which the encoder's VUI then says) and scales (StreamConfig.scale) in one pass.

use std::mem::ManuallyDrop;

use windows::core::Interface;
use windows::Win32::Foundation::RECT;
use windows::Win32::Graphics::Direct3D11::{
    ID3D11Texture2D, ID3D11VideoContext, ID3D11VideoDevice, ID3D11VideoProcessor, ID3D11VideoProcessorEnumerator,
    ID3D11VideoProcessorInputView, ID3D11VideoProcessorOutputView, D3D11_TEX2D_VPIV, D3D11_TEX2D_VPOV,
    D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE, D3D11_VIDEO_PROCESSOR_COLOR_SPACE, D3D11_VIDEO_PROCESSOR_CONTENT_DESC,
    D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC, D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC_0,
    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC, D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC_0, D3D11_VIDEO_PROCESSOR_STREAM,
    D3D11_VIDEO_USAGE_OPTIMAL_SPEED, D3D11_VPIV_DIMENSION_TEXTURE2D, D3D11_VPOV_DIMENSION_TEXTURE2D,
};
use windows::Win32::Graphics::Direct3D11::ID3D11VideoContext1;
use windows::Win32::Graphics::Dxgi::Common::{
    DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709, DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709, DXGI_RATIONAL,
};

use super::d3d::D3d;

/// D3D11_VIDEO_PROCESSOR_COLOR_SPACE's bits: Usage (bit 0), RGB_Range (bit 1: 0 full), YCbCr_Matrix
/// (bit 2: 1 BT.709), YCbCr_xvYCC (bit 3), Nominal_Range (bits 4–5: 1 is 16–235).
const INPUT_RGB_FULL: u32 = 0;
const OUTPUT_BT709_VIDEO_RANGE: u32 = (1 << 2) | (1 << 4);

pub struct Converter {
    video_context: ID3D11VideoContext,
    video_device: ID3D11VideoDevice,
    enumerator: ID3D11VideoProcessorEnumerator,
    processor: ID3D11VideoProcessor,
    /// The input view of the source texture last used (the stream's own copy: always the same).
    input: Option<(usize, ID3D11VideoProcessorInputView)>,
    outputs: Vec<ID3D11VideoProcessorOutputView>,
}

impl Converter {
    /// A converter from `in_w`×`in_h` BGRA to the NV12 `targets`, each `out_w`×`out_h`.
    pub fn new(
        d3d: &D3d,
        in_w: u32,
        in_h: u32,
        out_w: u32,
        out_h: u32,
        fps: u32,
        targets: &[ID3D11Texture2D],
    ) -> windows::core::Result<Self> {
        unsafe {
            let video_device: ID3D11VideoDevice = d3d.device.cast()?;
            let video_context: ID3D11VideoContext = d3d.context.cast()?;
            let rate = DXGI_RATIONAL { Numerator: fps.max(1), Denominator: 1 };
            let desc = D3D11_VIDEO_PROCESSOR_CONTENT_DESC {
                InputFrameFormat: D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE,
                InputFrameRate: rate,
                InputWidth: in_w,
                InputHeight: in_h,
                OutputFrameRate: rate,
                OutputWidth: out_w,
                OutputHeight: out_h,
                Usage: D3D11_VIDEO_USAGE_OPTIMAL_SPEED,
            };
            let enumerator = video_device.CreateVideoProcessorEnumerator(&desc)?;
            let processor = video_device.CreateVideoProcessor(&enumerator, 0)?;
            video_context.VideoProcessorSetStreamFrameFormat(&processor, 0, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
            video_context.VideoProcessorSetStreamAutoProcessingMode(&processor, 0, false);
            // The DXGI colour spaces (Windows 8.1+) where the driver has them: several drivers
            // ignore the older struct's nominal range. The older struct otherwise.
            if let Ok(context1) = video_context.cast::<ID3D11VideoContext1>() {
                context1.VideoProcessorSetStreamColorSpace1(&processor, 0, DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709);
                context1.VideoProcessorSetOutputColorSpace1(&processor, DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709);
            } else {
                video_context.VideoProcessorSetStreamColorSpace(
                    &processor,
                    0,
                    &D3D11_VIDEO_PROCESSOR_COLOR_SPACE { _bitfield: INPUT_RGB_FULL },
                );
                video_context.VideoProcessorSetOutputColorSpace(
                    &processor,
                    &D3D11_VIDEO_PROCESSOR_COLOR_SPACE { _bitfield: OUTPUT_BT709_VIDEO_RANGE },
                );
            }
            let full = RECT { left: 0, top: 0, right: out_w as i32, bottom: out_h as i32 };
            video_context.VideoProcessorSetStreamDestRect(&processor, 0, true, Some(&full));
            video_context.VideoProcessorSetOutputTargetRect(&processor, true, Some(&full));
            let mut outputs = Vec::with_capacity(targets.len());
            for target in targets {
                let desc = D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC {
                    ViewDimension: D3D11_VPOV_DIMENSION_TEXTURE2D,
                    Anonymous: D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC_0 { Texture2D: D3D11_TEX2D_VPOV { MipSlice: 0 } },
                };
                let mut view = None;
                video_device.CreateVideoProcessorOutputView(target, &enumerator, &desc, Some(&mut view))?;
                outputs.push(view.ok_or_else(windows::core::Error::empty)?);
            }
            Ok(Converter {
                video_context,
                video_device,
                enumerator,
                processor,
                input: None,
                outputs,
            })
        }
    }

    /// Draws `source` (its `content` part) into target `index`, scaled to fill it.
    pub fn convert(&mut self, source: &ID3D11Texture2D, content: RECT, index: usize) -> windows::core::Result<()> {
        unsafe {
            let key = source.as_raw() as usize;
            if self.input.as_ref().map(|(k, _)| *k) != Some(key) {
                let desc = D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC {
                    FourCC: 0,
                    ViewDimension: D3D11_VPIV_DIMENSION_TEXTURE2D,
                    Anonymous: D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC_0 {
                        Texture2D: D3D11_TEX2D_VPIV { MipSlice: 0, ArraySlice: 0 },
                    },
                };
                let mut view = None;
                self.video_device.CreateVideoProcessorInputView(source, &self.enumerator, &desc, Some(&mut view))?;
                self.input = Some((key, view.ok_or_else(windows::core::Error::empty)?));
            }
            let view = self.input.as_ref().map(|(_, v)| v.clone());
            self.video_context.VideoProcessorSetStreamSourceRect(&self.processor, 0, true, Some(&content));
            let stream = D3D11_VIDEO_PROCESSOR_STREAM {
                Enable: true.into(),
                OutputIndex: 0,
                InputFrameOrField: 0,
                PastFrames: 0,
                FutureFrames: 0,
                ppPastSurfaces: std::ptr::null_mut(),
                pInputSurface: ManuallyDrop::new(view),
                ppFutureSurfaces: std::ptr::null_mut(),
                ppPastSurfacesRight: std::ptr::null_mut(),
                pInputSurfaceRight: ManuallyDrop::new(None),
                ppFutureSurfacesRight: std::ptr::null_mut(),
            };
            let mut streams = [stream];
            let result = self.video_context.VideoProcessorBlt(&self.processor, &self.outputs[index], 0, &streams);
            ManuallyDrop::drop(&mut streams[0].pInputSurface);
            result
        }
    }

    pub fn targets(&self) -> usize {
        self.outputs.len()
    }
}
