#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
#![allow(non_upper_case_globals)]
#![allow(improper_ctypes)]
#![allow(dead_code)]

include!(concat!(env!("OUT_DIR"), "/aom_ffi.rs"));

use crate::codec::{base_bitrate, codec_thread_num};
use crate::{codec::EncoderApi, EncodeFrame, STRIDE_ALIGN};
use crate::{common::GoogleImage, generate_call_macro, generate_call_ptr_macro, Error, Result};
use crate::{EncodeInput, EncodeYuvFormat, Pixfmt};
use hbb_common::{
    anyhow::{anyhow, Context},
    bytes::Bytes,
    log,
    message_proto::{Chroma, EncodedVideoFrame, EncodedVideoFrames, VideoFrame},
    ResultType,
};
use std::os::raw::{c_int, c_uint};
use std::{ptr, slice};

generate_call_macro!(call_aom, false);
generate_call_ptr_macro!(call_aom_ptr);

impl Default for aom_codec_enc_cfg_t {
    fn default() -> Self {
        unsafe { std::mem::zeroed() }
    }
}

impl Default for aom_codec_ctx_t {
    fn default() -> Self {
        unsafe { std::mem::zeroed() }
    }
}

impl Default for aom_image_t {
    fn default() -> Self {
        unsafe { std::mem::zeroed() }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct AomEncoderConfig {
    pub width: u32,
    pub height: u32,
    pub quality: f32,
    pub keyframe_interval: Option<usize>,
}

pub struct AomEncoder {
    ctx: aom_codec_ctx_t,
    cfg: *mut aom_codec_enc_cfg_t,
    width: usize,
    height: usize,
    i444: bool,
    yuvfmt: EncodeYuvFormat,
}

const K_TIME_BASE_DEN: i64 = 1000;

extern "C" {
    fn scrap_aom_enc_cfg_new(
        iface: *const aom_codec_iface_t,
        width: c_uint,
        height: c_uint,
        threads: c_uint,
        q_min: c_uint,
        q_max: c_uint,
        bitrate: c_uint,
        keyframe_interval: c_uint,
        has_keyframe_interval: c_int,
        use_i444_profile: c_int,
    ) -> *mut aom_codec_enc_cfg_t;
    fn scrap_aom_enc_cfg_free(cfg: *mut aom_codec_enc_cfg_t);
    fn scrap_aom_enc_cfg_update_quality(
        cfg: *mut aom_codec_enc_cfg_t,
        q_min: c_uint,
        q_max: c_uint,
        bitrate: c_uint,
    ) -> aom_codec_err_t;
    fn scrap_aom_enc_cfg_bitrate(cfg: *const aom_codec_enc_cfg_t) -> c_uint;
    fn scrap_aom_apply_realtime_controls(
        ctx: *mut aom_codec_ctx_t,
        cfg: *const aom_codec_enc_cfg_t,
    ) -> aom_codec_err_t;
    fn scrap_aom_dec_cfg_new(threads: c_uint) -> *mut aom_codec_dec_cfg_t;
    fn scrap_aom_dec_cfg_free(cfg: *mut aom_codec_dec_cfg_t);
}

fn aom_failed_call(result: aom_codec_err_t, line: u32, column: u32) -> Error {
    Error::FailedCall(format!(
        "errcode={} {}:{}:{}:{}",
        result as i32,
        module_path!(),
        file!(),
        line,
        column
    ))
}

impl EncoderApi for AomEncoder {
    fn new(cfg: crate::codec::EncoderCfg, i444: bool) -> ResultType<Self>
    where
        Self: Sized,
    {
        match cfg {
            crate::codec::EncoderCfg::AOM(config) => {
                let i = call_aom_ptr!(aom_codec_av1_cx());
                let (q_min, q_max) = Self::calc_q_values(config.quality);
                let bitrate = Self::bitrate(config.width as _, config.height as _, config.quality);
                let keyframe_interval = config.keyframe_interval.unwrap_or_default() as c_uint;
                let c = call_aom_ptr!(scrap_aom_enc_cfg_new(
                    i,
                    config.width,
                    config.height,
                    codec_thread_num(64) as c_uint,
                    q_min,
                    q_max,
                    bitrate,
                    keyframe_interval,
                    config.keyframe_interval.is_some() as c_int,
                    i444 as c_int,
                ));

                let mut ctx = Default::default();
                // Flag options: AOM_CODEC_USE_PSNR and AOM_CODEC_USE_HIGHBITDEPTH
                let flags: aom_codec_flags_t = 0;
                let init_result = unsafe {
                    aom_codec_enc_init_ver(&mut ctx, i, c, flags, AOM_ENCODER_ABI_VERSION as _)
                };
                if init_result != aom_codec_err_t::AOM_CODEC_OK {
                    unsafe { scrap_aom_enc_cfg_free(c) };
                    return Err(aom_failed_call(init_result, line!(), column!()).into());
                }
                let controls_result = unsafe { scrap_aom_apply_realtime_controls(&mut ctx, c) };
                if controls_result != aom_codec_err_t::AOM_CODEC_OK {
                    unsafe {
                        aom_codec_destroy(&mut ctx);
                        scrap_aom_enc_cfg_free(c);
                    }
                    return Err(aom_failed_call(controls_result, line!(), column!()).into());
                }
                Ok(Self {
                    ctx,
                    cfg: c,
                    width: config.width as _,
                    height: config.height as _,
                    i444,
                    yuvfmt: Self::get_yuvfmt(config.width, config.height, i444),
                })
            }
            _ => Err(anyhow!("encoder type mismatch")),
        }
    }

    fn encode_to_message(&mut self, input: EncodeInput, ms: i64) -> ResultType<VideoFrame> {
        let mut frames = Vec::new();
        for ref frame in self
            .encode(ms, input.yuv()?, STRIDE_ALIGN)
            .with_context(|| "Failed to encode")?
        {
            frames.push(Self::create_frame(frame));
        }
        if frames.len() > 0 {
            Ok(Self::create_video_frame(frames))
        } else {
            Err(anyhow!("no valid frame"))
        }
    }

    fn yuvfmt(&self) -> crate::EncodeYuvFormat {
        self.yuvfmt.clone()
    }

    #[cfg(feature = "vram")]
    fn input_texture(&self) -> bool {
        false
    }

    fn set_quality(&mut self, ratio: f32) -> ResultType<()> {
        let (q_min, q_max) = Self::calc_q_values(ratio);
        let bitrate = Self::bitrate(self.width as _, self.height as _, ratio);
        call_aom!(scrap_aom_enc_cfg_update_quality(
            self.cfg, q_min, q_max, bitrate,
        ));
        call_aom!(aom_codec_enc_config_set(&mut self.ctx, self.cfg));
        Ok(())
    }

    fn bitrate(&self) -> u32 {
        unsafe { scrap_aom_enc_cfg_bitrate(self.cfg) }
    }

    fn support_changing_quality(&self) -> bool {
        true
    }

    fn latency_free(&self) -> bool {
        true
    }

    fn is_hardware(&self) -> bool {
        false
    }

    fn disable(&self) {}
}

impl AomEncoder {
    pub fn encode<'a>(
        &'a mut self,
        ms: i64,
        data: &[u8],
        stride_align: usize,
    ) -> Result<EncodeFrames<'a>> {
        let bpp = if self.i444 { 24 } else { 12 };
        if data.len() < self.width * self.height * bpp / 8 {
            return Err(Error::FailedCall("len not enough".to_string()));
        }
        let fmt = if self.i444 {
            aom_img_fmt::AOM_IMG_FMT_I444
        } else {
            aom_img_fmt::AOM_IMG_FMT_I420
        };

        let mut image = Default::default();
        call_aom_ptr!(aom_img_wrap(
            &mut image,
            fmt,
            self.width as _,
            self.height as _,
            stride_align as _,
            data.as_ptr() as _,
        ));
        let pts = K_TIME_BASE_DEN / 1000 * ms;
        let duration = K_TIME_BASE_DEN / 1000;
        call_aom!(aom_codec_encode(
            &mut self.ctx,
            &image,
            pts as _,
            duration as _, // Duration
            0,             // Flags
        ));

        Ok(EncodeFrames {
            ctx: &mut self.ctx,
            iter: ptr::null(),
        })
    }

    #[inline]
    pub fn create_video_frame(frames: Vec<EncodedVideoFrame>) -> VideoFrame {
        let mut vf = VideoFrame::new();
        let av1s = EncodedVideoFrames {
            frames: frames.into(),
            ..Default::default()
        };
        vf.set_av1s(av1s);
        vf
    }

    #[inline]
    fn create_frame(frame: &EncodeFrame) -> EncodedVideoFrame {
        EncodedVideoFrame {
            data: Bytes::from(frame.data.to_vec()),
            key: frame.key,
            pts: frame.pts,
            ..Default::default()
        }
    }

    fn bitrate(width: u32, height: u32, ratio: f32) -> u32 {
        let bitrate = base_bitrate(width, height) as f32;
        (bitrate * ratio) as u32
    }

    #[inline]
    fn calc_q_values(ratio: f32) -> (u32, u32) {
        let b = (ratio * 100.0) as u32;
        let b = std::cmp::min(b, 200);
        let q_min1 = 24;
        let q_min2 = 5;
        let q_max1 = 45;
        let q_max2 = 25;

        let t = b as f32 / 200.0;

        let mut q_min: u32 = ((1.0 - t) * q_min1 as f32 + t * q_min2 as f32).round() as u32;
        let mut q_max = ((1.0 - t) * q_max1 as f32 + t * q_max2 as f32).round() as u32;

        q_min = q_min.clamp(q_min2, q_min1);
        q_max = q_max.clamp(q_max2, q_max1);

        (q_min, q_max)
    }

    fn get_yuvfmt(width: u32, height: u32, i444: bool) -> EncodeYuvFormat {
        let mut img = Default::default();
        let fmt = if i444 {
            aom_img_fmt::AOM_IMG_FMT_I444
        } else {
            aom_img_fmt::AOM_IMG_FMT_I420
        };
        unsafe {
            aom_img_wrap(
                &mut img,
                fmt,
                width as _,
                height as _,
                crate::STRIDE_ALIGN as _,
                0x1 as _,
            );
        }
        let pixfmt = if i444 { Pixfmt::I444 } else { Pixfmt::I420 };
        EncodeYuvFormat {
            pixfmt,
            w: img.w as _,
            h: img.h as _,
            stride: img.stride.map(|s| s as usize).to_vec(),
            u: img.planes[1] as usize - img.planes[0] as usize,
            v: img.planes[2] as usize - img.planes[0] as usize,
        }
    }
}

impl Drop for AomEncoder {
    fn drop(&mut self) {
        unsafe {
            let result = aom_codec_destroy(&mut self.ctx);
            scrap_aom_enc_cfg_free(self.cfg);
            if result != aom_codec_err_t::AOM_CODEC_OK {
                panic!("failed to destroy aom codec");
            }
        }
    }
}

pub struct EncodeFrames<'a> {
    ctx: &'a mut aom_codec_ctx_t,
    iter: aom_codec_iter_t,
}

impl<'a> Iterator for EncodeFrames<'a> {
    type Item = EncodeFrame<'a>;
    fn next(&mut self) -> Option<Self::Item> {
        loop {
            unsafe {
                let pkt = aom_codec_get_cx_data(self.ctx, &mut self.iter);
                if pkt.is_null() {
                    return None;
                } else if (*pkt).kind == aom_codec_cx_pkt_kind::AOM_CODEC_CX_FRAME_PKT {
                    let f = &(*pkt).data.frame;
                    return Some(Self::Item {
                        data: slice::from_raw_parts(f.buf as _, f.sz as _),
                        key: (f.flags & AOM_FRAME_IS_KEY) != 0,
                        pts: f.pts,
                    });
                } else {
                    // Ignore the packet.
                }
            }
        }
    }
}

pub struct AomDecoder {
    ctx: aom_codec_ctx_t,
}

impl AomDecoder {
    pub fn new() -> Result<Self> {
        let i = call_aom_ptr!(aom_codec_av1_dx());
        let mut ctx = Default::default();
        let cfg = call_aom_ptr!(scrap_aom_dec_cfg_new(codec_thread_num(64) as c_uint));
        let init_result =
            unsafe { aom_codec_dec_init_ver(&mut ctx, i, cfg, 0, AOM_DECODER_ABI_VERSION as _) };
        unsafe { scrap_aom_dec_cfg_free(cfg) };
        if init_result != aom_codec_err_t::AOM_CODEC_OK {
            return Err(aom_failed_call(init_result, line!(), column!()));
        }
        Ok(Self { ctx })
    }

    pub fn decode<'a>(&'a mut self, data: &[u8]) -> Result<DecodeFrames<'a>> {
        call_aom!(aom_codec_decode(
            &mut self.ctx,
            data.as_ptr(),
            data.len() as _,
            ptr::null_mut(),
        ));

        Ok(DecodeFrames {
            ctx: &mut self.ctx,
            iter: ptr::null(),
        })
    }

    /// Notify the decoder to return any pending frame
    pub fn flush<'a>(&'a mut self) -> Result<DecodeFrames<'a>> {
        call_aom!(aom_codec_decode(
            &mut self.ctx,
            ptr::null(),
            0,
            ptr::null_mut(),
        ));
        Ok(DecodeFrames {
            ctx: &mut self.ctx,
            iter: ptr::null(),
        })
    }
}

impl Drop for AomDecoder {
    fn drop(&mut self) {
        unsafe {
            let result = aom_codec_destroy(&mut self.ctx);
            if result != aom_codec_err_t::AOM_CODEC_OK {
                panic!("failed to destroy aom codec");
            }
        }
    }
}

pub struct DecodeFrames<'a> {
    ctx: &'a mut aom_codec_ctx_t,
    iter: aom_codec_iter_t,
}

impl<'a> Iterator for DecodeFrames<'a> {
    type Item = Image;
    fn next(&mut self) -> Option<Self::Item> {
        let img = unsafe { aom_codec_get_frame(self.ctx, &mut self.iter) };
        if img.is_null() {
            return None;
        } else {
            return Some(Image(img));
        }
    }
}

pub struct Image(*mut aom_image_t);
impl Image {
    #[inline]
    pub fn new() -> Self {
        Self(std::ptr::null_mut())
    }

    #[inline]
    pub fn is_null(&self) -> bool {
        self.0.is_null()
    }

    #[inline]
    pub fn format(&self) -> aom_img_fmt_t {
        self.inner().fmt
    }

    #[inline]
    pub fn inner(&self) -> &aom_image_t {
        unsafe { &*self.0 }
    }
}

impl GoogleImage for Image {
    #[inline]
    fn width(&self) -> usize {
        self.inner().d_w as _
    }

    #[inline]
    fn height(&self) -> usize {
        self.inner().d_h as _
    }

    #[inline]
    fn stride(&self) -> Vec<i32> {
        self.inner().stride.iter().map(|x| *x as i32).collect()
    }

    #[inline]
    fn planes(&self) -> Vec<*mut u8> {
        self.inner().planes.iter().map(|p| *p as *mut u8).collect()
    }

    fn chroma(&self) -> Chroma {
        match self.inner().fmt {
            aom_img_fmt::AOM_IMG_FMT_I444 => Chroma::I444,
            _ => Chroma::I420,
        }
    }
}

impl Drop for Image {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe { aom_img_free(self.0) };
        }
    }
}

unsafe impl Send for aom_codec_ctx_t {}
