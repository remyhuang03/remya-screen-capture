use anyhow::{Context, Result, ensure};
use image::RgbaImage;

use crate::api::{ScrollStatus, ScrollUpdate};
use crate::capture::{crop, encode_png, encode_rgba_png, scroll_frame};
use crate::scroll_sheet::{Fold, Refusal, ScrollSheet, SheetLimits, preview_slice, preview_window};

const MAX_SCROLL_PIXELS: u32 = 40_000_000;
const PREVIEW_WIDTH: u32 = 320;
const PREVIEW_HEIGHT: u32 = 640;

pub(crate) struct ScrollSession {
    output: String,
    rect: [u32; 4],
    output_size: (u32, u32),
    sheet: ScrollSheet,
    max_height: u32,
    frames: u32,
    show_seed: bool,
    full: bool,
}

impl ScrollSession {
    pub(crate) fn start(output: String, rect: [u32; 4]) -> Result<Self> {
        let source = scroll_frame(&output)?;
        let seed = crop(&source, rect)?;
        let mut limits = SheetLimits::default();
        limits.max_height = limits.max_height.min(MAX_SCROLL_PIXELS / seed.width());
        ensure!(
            seed.height() < limits.max_height,
            "The scroll selection is too large"
        );
        let sheet = ScrollSheet::new(seed.width(), seed.height(), seed.as_raw(), limits)
            .map_err(|_| anyhow::anyhow!("Select a taller or wider area for scrolling capture"))?;
        Ok(Self {
            output,
            rect,
            output_size: source.dimensions(),
            sheet,
            max_height: limits.max_height,
            frames: 1,
            show_seed: true,
            full: false,
        })
    }

    pub(crate) fn sample(&mut self) -> Result<ScrollUpdate> {
        if self.full {
            return self.update(ScrollStatus::Full, false);
        }
        if self.show_seed {
            self.show_seed = false;
            return self.update(ScrollStatus::Appended, true);
        }

        let source = scroll_frame(&self.output)?;
        ensure!(
            source.dimensions() == self.output_size,
            "The display size changed during scrolling capture"
        );
        let frame = crop(&source, self.rect)?;
        match self.sheet.push(frame.as_raw()) {
            Fold::GrewBottom { .. } | Fold::GrewTop { .. } | Fold::Shifted { .. } => {
                self.frames = self.frames.saturating_add(1);
                self.full = self.sheet.dimensions().1 >= self.max_height;
                let status = if self.full {
                    ScrollStatus::Full
                } else {
                    ScrollStatus::Appended
                };
                self.update(status, true)
            }
            Fold::Unchanged | Fold::Still => self.update(ScrollStatus::Unchanged, false),
            Fold::Refused(Refusal::TooTall) => {
                self.full = true;
                self.update(ScrollStatus::Full, false)
            }
            Fold::Refused(_) => self.update(ScrollStatus::NoMatch, false),
        }
    }

    fn update(&self, status: ScrollStatus, show_preview: bool) -> Result<ScrollUpdate> {
        let (width, height) = self.sheet.dimensions();
        let preview = if show_preview {
            let (viewport_top, viewport_height) = self.sheet.viewport_span();
            let rows = PREVIEW_HEIGHT * width.div_ceil(PREVIEW_WIDTH);
            let (top, rows) = preview_window(height, viewport_top, viewport_height, rows);
            let (width, height, pixels) =
                preview_slice(self.sheet.canvas(), width, height, top, rows, PREVIEW_WIDTH);
            let image = RgbaImage::from_raw(width, height, pixels)
                .context("Could not build the scrolling preview")?;
            Some(encode_png(&image)?)
        } else {
            None
        };
        Ok(ScrollUpdate {
            frames: self.frames,
            width,
            height,
            preview,
            status,
        })
    }

    pub(crate) fn finish(&self) -> Result<Vec<u8>> {
        let (width, height) = self.sheet.dimensions();
        encode_rgba_png(width, height, self.sheet.canvas())
    }
}
