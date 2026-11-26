//! QR code detection for the screenshot selection tools.

use anyhow::Result;
use image::{ImageFormat, imageops};

use crate::capture::decode;

/// Text of every readable QR code in the PNG, in detection order, without duplicates.
pub(crate) fn scan_png(png: &[u8]) -> Result<Vec<String>> {
    let gray = imageops::grayscale(&decode(png, ImageFormat::Png)?);
    let mut prepared = rqrr::PreparedImage::prepare_from_greyscale(
        gray.width() as usize,
        gray.height() as usize,
        |x, y| gray.get_pixel(x as u32, y as u32).0[0],
    );
    let mut texts = Vec::new();
    // A damaged or partly selected code is skipped rather than failing the scan.
    for (_, text) in prepared
        .detect_grids()
        .into_iter()
        .filter_map(|grid| grid.decode().ok())
    {
        if !texts.contains(&text) {
            texts.push(text);
        }
    }
    Ok(texts)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::capture::encode_png;
    use image::{Rgba, RgbaImage};
    use qrcode::{Color, QrCode};

    fn qr_png(text: &str) -> Result<Vec<u8>> {
        let code = QrCode::new(text)?;
        let width = code.width() as u32;
        let colors = code.to_colors();
        let (scale, quiet) = (6, 4);
        let side = (width + 2 * quiet) * scale;
        let image = RgbaImage::from_fn(side, side, |x, y| {
            let (x, y) = (x / scale, y / scale);
            let dark = (quiet..width + quiet).contains(&x)
                && (quiet..width + quiet).contains(&y)
                && colors[((y - quiet) * width + x - quiet) as usize] == Color::Dark;
            Rgba(if dark { [0, 0, 0, 255] } else { [255; 4] })
        });
        encode_png(&image)
    }

    #[test]
    fn scan_reads_codes_and_ignores_blank_images() -> Result<()> {
        let url = "https://example.com/remya";
        assert_eq!(scan_png(&qr_png(url)?)?, [url]);
        let blank = encode_png(&RgbaImage::from_pixel(64, 64, Rgba([255; 4])))?;
        assert!(scan_png(&blank)?.is_empty());
        assert!(scan_png(b"not a png").is_err());
        Ok(())
    }
}
