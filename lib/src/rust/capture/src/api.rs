use anyhow::Result;
use flutter_rust_bridge::frb;
use std::sync::Mutex;

use crate::{capture, files, scroll::ScrollSession};

pub fn capture_output(name: String) -> Result<Vec<u8>> {
    capture::output_png(&name)
}

pub fn capture_window(stable_id: String) -> Result<Vec<u8>> {
    capture::window_png(&stable_id)
}

pub fn crop_png(png: Vec<u8>, x: u32, y: u32, width: u32, height: u32) -> Result<Vec<u8>> {
    capture::crop_png(&png, [x, y, width, height])
}

pub fn copy_png(png: Vec<u8>) -> Result<()> {
    files::copy_png(&png)
}

pub fn save_png(png: Vec<u8>, path: String, replace: bool, unique: bool) -> Result<String> {
    files::save_png(&png, &path, replace, unique)
}

pub fn begin_scroll(
    output: String,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) -> Result<ScrollCapture> {
    Ok(ScrollCapture(Mutex::new(ScrollSession::start(
        output,
        [x, y, width, height],
    )?)))
}

#[frb(opaque)]
pub struct ScrollCapture(Mutex<ScrollSession>);

impl ScrollCapture {
    /// The selection as captured before scrolling.
    pub fn seed(&self) -> Result<ScrollUpdate> {
        self.session()?.seed()
    }

    /// Scrolls the selection once and stitches what it reveals.
    pub fn step(&self) -> Result<ScrollUpdate> {
        self.session()?.step()
    }

    pub fn finish(&self) -> Result<Vec<u8>> {
        self.session()?.finish()
    }

    fn session(&self) -> Result<std::sync::MutexGuard<'_, ScrollSession>> {
        self.0
            .lock()
            .map_err(|_| anyhow::anyhow!("The scrolling capture stopped unexpectedly"))
    }
}

pub struct ScrollUpdate {
    pub frames: u32,
    pub width: u32,
    pub height: u32,
    pub preview: Vec<u8>,
    pub status: ScrollStatus,
}

#[derive(Clone, Copy)]
pub enum ScrollStatus {
    /// New content was stitched; keep scrolling.
    Appended,
    /// Scrolling no longer moves the content.
    End,
    /// The image reached its maximum size.
    Full,
    /// The scrolled content could not be aligned with the capture.
    NoMatch,
}
