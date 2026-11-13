//! Joins equally sized RGBA frames, each scrolled further down than the last,
//! into one tall image.
//!
//! Each row is reduced to [`BINS`] column means of luma. The vertical shift
//! between two frames is the offset whose overlapping rows agree best. Rows
//! that are byte-identical at the same position in both frames (pinned headers
//! and footers) are left out of matching, and the footer is kept once at the
//! bottom of the sheet.

use image::RgbaImage;
use image::imageops::{FilterType, resize};

const BINS: usize = 32;
/// Per-bin difference cap, so a moving scrollbar thumb or hover highlight
/// cannot outweigh the rest of the row.
const BIN_CAP: u16 = 32;
const ACCEPT_COST: f32 = 4.0;
const MIN_EVIDENCE: usize = 8;
const RANK_ROWS: usize = 192;

type Signature = [u8; BINS];

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Fold {
    Appended(u32),
    Unchanged,
    NoMatch,
    Full,
}

pub(crate) struct Stitch {
    width: u32,
    height: u32,
    max_height: u32,
    sheet: Vec<u8>,
    last: Vec<u8>,
    last_rows: Vec<Signature>,
}

impl Stitch {
    pub(crate) fn new(width: u32, height: u32, seed: Vec<u8>, max_height: u32) -> Self {
        let last_rows = signatures(&seed, width, height);
        Self {
            width,
            height,
            max_height,
            sheet: seed.clone(),
            last: seed,
            last_rows,
        }
    }

    pub(crate) fn dimensions(&self) -> (u32, u32) {
        (self.width, (self.sheet.len() / self.row_bytes()) as u32)
    }

    pub(crate) fn pixels(&self) -> &[u8] {
        &self.sheet
    }

    /// Places `frame` below the previous frame. `expected` is the shift the
    /// caller predicts, used only to break ties on repetitive content.
    pub(crate) fn push(&mut self, frame: &[u8], expected: Option<u32>) -> Fold {
        let row = self.row_bytes();
        let h = self.height as usize;
        debug_assert_eq!(frame.len(), row * h);
        let same = |y: usize| frame[y * row..][..row] == self.last[y * row..][..row];
        let mut top = 0;
        while top < h && same(top) {
            top += 1;
        }
        if top == h {
            return Fold::Unchanged;
        }
        let mut bottom = 0;
        while same(h - 1 - bottom) {
            bottom += 1;
        }
        let cap = h / 3;
        let (top, bottom) = (top.min(cap), bottom.min(cap));

        let rows = signatures(frame, self.width, self.height);
        let Some(dy) = best_shift(&self.last_rows, &rows, top, h - bottom, expected) else {
            return Fold::NoMatch;
        };
        if dy == 0 {
            self.remember(frame, rows);
            return Fold::Unchanged;
        }
        if self.dimensions().1 as usize + dy > self.max_height as usize {
            return Fold::Full;
        }
        // The sheet ends with the previous frame's footer, which equals this
        // frame's footer: replace it with the newly exposed rows plus footer.
        self.sheet.truncate(self.sheet.len() - bottom * row);
        self.sheet
            .extend_from_slice(&frame[(h - bottom - dy) * row..]);
        self.remember(frame, rows);
        Fold::Appended(dy as u32)
    }

    /// The bottom of the sheet, at most `max_width` × `max_height`.
    pub(crate) fn preview(&self, max_width: u32, max_height: u32) -> RgbaImage {
        let (width, height) = self.dimensions();
        let scale = (max_width as f32 / width as f32).min(1.0);
        let rows = ((max_height as f32 / scale) as u32).clamp(1, height);
        let start = (height - rows) as usize * self.row_bytes();
        let tail = RgbaImage::from_raw(width, rows, self.sheet[start..].to_vec())
            .expect("sheet rows are whole RGBA rows");
        if scale >= 1.0 {
            return tail;
        }
        let size = |value: u32| ((value as f32 * scale).round() as u32).max(1);
        resize(&tail, size(width), size(rows), FilterType::Triangle)
    }

    fn remember(&mut self, frame: &[u8], rows: Vec<Signature>) {
        self.last.copy_from_slice(frame);
        self.last_rows = rows;
    }

    fn row_bytes(&self) -> usize {
        self.width as usize * 4
    }
}

fn signatures(rgba: &[u8], width: u32, height: u32) -> Vec<Signature> {
    let width = width as usize;
    let bounds: Vec<(usize, usize)> = (0..BINS)
        .map(|bin| {
            let start = (bin * width / BINS).min(width - 1);
            (start, ((bin + 1) * width / BINS).clamp(start + 1, width))
        })
        .collect();
    rgba.chunks_exact(width * 4)
        .take(height as usize)
        .map(|row| {
            let mut signature = [0; BINS];
            for (value, &(start, end)) in signature.iter_mut().zip(&bounds) {
                let sum: u32 = row[start * 4..end * 4]
                    .as_chunks::<4>()
                    .0
                    .iter()
                    .map(|p| (p[0] as u32 * 77 + p[1] as u32 * 150 + p[2] as u32 * 29) >> 8)
                    .sum();
                *value = (sum / (end - start) as u32) as u8;
            }
            signature
        })
        .collect()
}

fn row_cost(a: &Signature, b: &Signature) -> u16 {
    a.iter()
        .zip(b)
        .map(|(&a, &b)| (a.abs_diff(b) as u16).min(BIN_CAP))
        .sum()
}

/// Mean per-bin cost of matching `next[y]` against `previous[y + dy]` over
/// `evidence` rows that fit inside `end`, or `None` without enough evidence.
fn shift_cost(
    previous: &[Signature],
    next: &[Signature],
    evidence: &[usize],
    end: usize,
    dy: usize,
    stride: usize,
) -> Option<f32> {
    let (mut total, mut count) = (0u32, 0usize);
    for &y in evidence.iter().take_while(|&&y| y + dy < end) {
        count += 1;
        if count % stride == 0 {
            total += row_cost(&next[y], &previous[y + dy]) as u32;
        }
    }
    (count >= MIN_EVIDENCE).then(|| total as f32 / (count / stride) as f32 / BINS as f32)
}

/// The downward shift of `next` relative to `previous` within rows
/// `start..end`, or `None` when no shift is clearly better than the rest.
fn best_shift(
    previous: &[Signature],
    next: &[Signature],
    start: usize,
    end: usize,
    expected: Option<u32>,
) -> Option<usize> {
    let band = end.saturating_sub(start);
    let min_overlap = (band / 8).max(24);
    if band <= min_overlap {
        return None;
    }
    // Only rows that differ from the row above can tell offsets apart; blank
    // runs would otherwise match at every shift.
    let evidence: Vec<usize> = (start + 1..end)
        .filter(|&y| row_cost(&next[y], &next[y - 1]) >= 8)
        .collect();
    let stride = (evidence.len() / RANK_ROWS).max(1);
    let ranked: Vec<(usize, f32)> = (0..=band - min_overlap)
        .filter_map(|dy| Some((dy, shift_cost(previous, next, &evidence, end, dy, stride)?)))
        .collect();

    // Verify the best local minima with every evidence row.
    let mut minima: Vec<(usize, f32)> = ranked
        .iter()
        .enumerate()
        .filter(|&(i, &(_, cost))| {
            ranked
                .get(i.wrapping_sub(1))
                .is_none_or(|left| left.1 >= cost)
                && ranked.get(i + 1).is_none_or(|right| right.1 > cost)
        })
        .map(|(_, &candidate)| candidate)
        .collect();
    minima.sort_by(|a, b| a.1.total_cmp(&b.1));
    let mut verified: Vec<(usize, f32)> = minima
        .into_iter()
        .take(4)
        .filter_map(|(dy, _)| Some((dy, shift_cost(previous, next, &evidence, end, dy, 1)?)))
        .collect();
    verified.sort_by(|a, b| a.1.total_cmp(&b.1));

    let &(best, cost) = verified.first()?;
    if cost > ACCEPT_COST {
        return None;
    }
    let rivals: Vec<usize> = verified
        .iter()
        .filter(|&&(dy, other)| dy.abs_diff(best) > 2 && other <= cost * 1.5 + 0.5)
        .map(|&(dy, _)| dy)
        .collect();
    if rivals.is_empty() {
        return Some(best);
    }
    // Repetitive content fits several shifts; trust the prediction if any.
    let expected = expected? as usize;
    std::iter::once(best)
        .chain(rivals)
        .min_by_key(|dy| dy.abs_diff(expected))
}

#[cfg(test)]
mod tests {
    use super::*;

    const W: u32 = 96;
    const H: u32 = 200;

    /// A page of pseudo-random text lines separated by blank rows.
    fn page(height: u32, seed: u32) -> Vec<u8> {
        let mut state = seed;
        let mut next = move || {
            state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            state >> 16
        };
        let mut pixels = Vec::with_capacity((W * height * 4) as usize);
        let mut glyphs = vec![false; W as usize];
        for y in 0..height {
            if y % 14 == 0 {
                let words = next() % 6 + 2;
                glyphs.fill(false);
                let mut x = 2;
                for _ in 0..words {
                    let len = (next() % 14 + 3) as usize;
                    for g in glyphs.iter_mut().skip(x).take(len) {
                        *g = true;
                    }
                    x += len + 3;
                    if x >= W as usize {
                        break;
                    }
                }
            }
            let ink = y % 14 < 10;
            for &glyph in &glyphs {
                let on = ink && glyph && (next() % 3 != 0);
                let v = if on { 30 } else { 250 };
                pixels.extend_from_slice(&[v, v, v, 255]);
            }
        }
        pixels
    }

    fn rows(pixels: &[u8], start: u32, count: u32) -> Vec<u8> {
        let row = (W * 4) as usize;
        pixels[start as usize * row..(start + count) as usize * row].to_vec()
    }

    fn stitch_offsets(page: &[u8], offsets: &[u32]) -> (Stitch, Vec<Fold>) {
        let mut stitch = Stitch::new(W, H, rows(page, offsets[0], H), 20_000);
        let folds = offsets[1..]
            .iter()
            .map(|&y| stitch.push(&rows(page, y, H), None))
            .collect();
        (stitch, folds)
    }

    #[test]
    fn rebuilds_the_page_from_shifted_frames() {
        let page = page(700, 7);
        let (stitch, folds) = stitch_offsets(&page, &[0, 60, 150, 247, 340, 500]);
        assert_eq!(
            folds,
            [60, 90, 97, 93, 160].map(Fold::Appended),
            "every shift is recovered"
        );
        assert_eq!(stitch.dimensions(), (W, 700));
        assert!(stitch.pixels() == page.as_slice());
    }

    #[test]
    fn keeps_pinned_header_and_footer_once() {
        let content = page(800, 3);
        let header = vec![90; (W * 24 * 4) as usize];
        let footer = vec![160; (W * 16 * 4) as usize];
        let frame = |y: u32| [header.clone(), rows(&content, y, H - 40), footer.clone()].concat();
        let mut stitch = Stitch::new(W, H, frame(0), 20_000);
        let mut previous = 0;
        for y in [70, 140, 230] {
            assert_eq!(stitch.push(&frame(y), None), Fold::Appended(y - previous));
            previous = y;
        }
        let expected = [header, rows(&content, 0, 230 + H - 40), footer].concat();
        assert!(stitch.pixels() == expected.as_slice());
    }

    #[test]
    fn tolerates_a_moving_scrollbar() {
        let content = page(600, 11);
        let frame = |y: u32| {
            let mut pixels = rows(&content, y, H);
            for row in 0..H {
                let thumb = (y / 3..y / 3 + 40).contains(&row);
                let v = if thumb { 60 } else { 230 };
                let at = ((row * W + W - 4) * 4) as usize;
                for px in pixels[at..at + 16].as_chunks_mut::<4>().0 {
                    px.copy_from_slice(&[v, v, v, 255]);
                }
            }
            pixels
        };
        let mut stitch = Stitch::new(W, H, frame(0), 20_000);
        assert_eq!(stitch.push(&frame(80), None), Fold::Appended(80));
        assert_eq!(stitch.push(&frame(170), None), Fold::Appended(90));
    }

    #[test]
    fn refuses_frames_without_evidence() {
        let blank = vec![250; (W * H * 4) as usize];
        let mut stitch = Stitch::new(W, H, blank.clone(), 20_000);
        assert_eq!(stitch.push(&blank, None), Fold::Unchanged);
        let mut marked = blank;
        marked[(W * 4 * 100) as usize] = 0;
        assert_eq!(stitch.push(&marked, None), Fold::NoMatch);
    }

    #[test]
    fn detects_the_end_and_the_height_limit() {
        let page = page(330, 5);
        let (mut stitch, folds) = stitch_offsets(&page, &[0, 100, 130]);
        assert_eq!(folds, [Fold::Appended(100), Fold::Appended(30)]);
        assert_eq!(stitch.push(&rows(&page, 130, H), None), Fold::Unchanged);
        assert!(stitch.pixels() == page.as_slice());

        let mut capped = Stitch::new(W, H, rows(&page, 0, H), 250);
        assert_eq!(capped.push(&rows(&page, 100, H), None), Fold::Full);
        assert_eq!(capped.dimensions(), (W, H));
    }

    #[test]
    fn uses_the_prediction_on_repetitive_content() {
        let tile = page(30, 9);
        let repeated: Vec<u8> = (0..20).flat_map(|_| tile.clone()).collect();
        let mut stitch = Stitch::new(W, H, rows(&repeated, 0, H), 20_000);
        // A 30-row period makes 15, 45, 75… equally good fits for a 45-row step.
        assert_eq!(stitch.push(&rows(&repeated, 45, H), None), Fold::NoMatch);
        assert_eq!(
            stitch.push(&rows(&repeated, 45, H), Some(50)),
            Fold::Appended(45)
        );
    }

    #[test]
    fn previews_the_bottom_of_the_sheet() {
        let page = page(700, 1);
        let (stitch, _) = stitch_offsets(&page, &[0, 100, 200, 300, 400, 500]);
        let preview = stitch.preview(48, 100);
        assert_eq!(preview.dimensions(), (48, 100));
        let full = stitch.preview(320, 640);
        assert_eq!(full.dimensions(), (W, 640));
        assert!(full.as_raw().as_slice() == &page[(60 * W * 4) as usize..]);
    }
}
