//! Auto-scrolling capture: turn the wheel over the selection, wait for the
//! content to settle, capture it and stitch it below what came before.

mod pointer;
mod stitch;

use anyhow::{Context, Result, ensure};
use image::RgbaImage;
use std::thread::sleep;
use std::time::{Duration, Instant};

use crate::api::{ScrollStatus, ScrollUpdate};
use crate::capture::{crop, encode_png, encode_rgba_png, scroll_frame};
use pointer::VirtualPointer;
use stitch::{Fold, Stitch};

const MAX_SCROLL_PIXELS: u32 = 40_000_000;
const MAX_HEIGHT: u32 = 20_000;
const PREVIEW_WIDTH: u32 = 320;
const PREVIEW_HEIGHT: u32 = 640;
const MAX_NOTCHES: i32 = 10;
/// Wheel attempts per step before giving up on a frame that does not fit.
const ATTEMPTS: u32 = 4;
/// Consecutive scrolls without movement that mean the end was reached.
const END_AFTER: u32 = 2;

pub(crate) struct ScrollSession {
    output: String,
    rect: [u32; 4],
    output_size: (u32, u32),
    pointer: VirtualPointer,
    stitch: Stitch,
    notches: i32,
    pixels_per_notch: Option<f32>,
    frames: u32,
    stopped: Option<ScrollStatus>,
}

impl ScrollSession {
    pub(crate) fn start(output: String, rect: [u32; 4]) -> Result<Self> {
        let pointer = VirtualPointer::new(&output)?;
        let output_size = scroll_frame(&output)?.dimensions();
        let seed = settled(&output, rect, output_size)?;
        let max_height = MAX_HEIGHT.min(MAX_SCROLL_PIXELS / seed.width());
        ensure!(
            seed.height() < max_height,
            "The scroll selection is too large"
        );
        let stitch = Stitch::new(seed.width(), seed.height(), seed.into_raw(), max_height);
        Ok(Self {
            output,
            rect,
            output_size,
            pointer,
            stitch,
            notches: 1,
            pixels_per_notch: None,
            frames: 1,
            stopped: None,
        })
    }

    /// The seed frame, before any scrolling.
    pub(crate) fn seed(&self) -> Result<ScrollUpdate> {
        self.update(ScrollStatus::Appended)
    }

    /// Scrolls once and appends the newly exposed content.
    pub(crate) fn step(&mut self) -> Result<ScrollUpdate> {
        if let Some(status) = self.stopped {
            return self.update(status);
        }
        let mut unchanged = 0;
        for _ in 0..ATTEMPTS {
            self.scroll(self.notches)?;
            let frame = settled(&self.output, self.rect, self.output_size)?;
            let expected = self
                .pixels_per_notch
                .map(|pixels| (pixels * self.notches as f32).round() as u32);
            match self.stitch.push(frame.as_raw(), expected) {
                Fold::Appended(dy) => {
                    self.frames += 1;
                    let pixels = dy as f32 / self.notches as f32;
                    self.pixels_per_notch = Some(pixels);
                    // Aim for half a selection per step: plenty of overlap.
                    self.notches =
                        ((self.rect[3] as f32 * 0.5 / pixels) as i32).clamp(1, MAX_NOTCHES);
                    return self.update(ScrollStatus::Appended);
                }
                Fold::Unchanged => {
                    unchanged += 1;
                    if unchanged >= END_AFTER {
                        return self.stop(ScrollStatus::End);
                    }
                }
                Fold::Full => return self.stop(ScrollStatus::Full),
                Fold::NoMatch => {
                    // Return to the last stitched position and try a smaller step.
                    self.scroll(-self.notches)?;
                    settled(&self.output, self.rect, self.output_size)?;
                    self.notches = (self.notches / 2).max(1);
                }
            }
        }
        self.update(ScrollStatus::NoMatch)
    }

    pub(crate) fn finish(&self) -> Result<Vec<u8>> {
        let (width, height) = self.stitch.dimensions();
        encode_rgba_png(width, height, self.stitch.pixels())
    }

    fn scroll(&self, notches: i32) -> Result<()> {
        let [x, y, width, height] = self.rect;
        let (output_width, output_height) = self.output_size;
        self.pointer.scroll(
            [x + width / 2, y + height / 2, output_width, output_height],
            notches,
        )
    }

    fn stop(&mut self, status: ScrollStatus) -> Result<ScrollUpdate> {
        self.stopped = Some(status);
        self.update(status)
    }

    fn update(&self, status: ScrollStatus) -> Result<ScrollUpdate> {
        let (width, height) = self.stitch.dimensions();
        Ok(ScrollUpdate {
            frames: self.frames,
            width,
            height,
            preview: encode_png(&self.stitch.preview(PREVIEW_WIDTH, PREVIEW_HEIGHT))?,
            status,
        })
    }
}

/// Captures the selection once it stops changing, so smooth-scroll
/// animations and repaints have finished.
fn settled(output: &str, rect: [u32; 4], size: (u32, u32)) -> Result<RgbaImage> {
    let grab = || -> Result<RgbaImage> {
        let source = scroll_frame(output)?;
        ensure!(
            source.dimensions() == size,
            "The display size changed during scrolling capture"
        );
        crop(&source, rect).context("Could not crop the scrolling frame")
    };
    sleep(Duration::from_millis(60));
    let deadline = Instant::now() + Duration::from_secs(1);
    let mut previous = grab()?;
    loop {
        sleep(Duration::from_millis(40));
        let frame = grab()?;
        if frame == previous || Instant::now() >= deadline {
            return Ok(frame);
        }
        previous = frame;
    }
}
