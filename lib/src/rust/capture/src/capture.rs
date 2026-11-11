use anyhow::{Context, Result, ensure};
use image::codecs::png::{CompressionType, FilterType, PngEncoder};
use image::{
    ExtendedColorType, GenericImageView, ImageEncoder, ImageFormat, ImageReader, RgbaImage,
};
use std::io::Cursor;
use std::process::Command;

pub(crate) fn output_png(name: &str) -> Result<Vec<u8>> {
    ensure!(!name.is_empty(), "Select a display to capture");
    let png = grim(["-t", "png", "-l", "1", "-o", name, "-"])?;
    check_png(&png)?;
    Ok(png)
}

pub(crate) fn window_png(stable_id: &str) -> Result<Vec<u8>> {
    ensure!(
        !stable_id.is_empty() && stable_id.bytes().all(|byte| byte.is_ascii_hexdigit()),
        "The selected window has no valid Hyprland identifier"
    );
    let png = grim(["-t", "png", "-l", "1", "-T", stable_id, "-"])?;
    check_png(&png)?;
    Ok(png)
}

pub(crate) fn scroll_frame(name: &str) -> Result<RgbaImage> {
    ensure!(!name.is_empty(), "Select a display to capture");
    let ppm = grim(["-t", "ppm", "-o", name, "-"])?;
    decode(&ppm, ImageFormat::Pnm)
}

fn grim<const N: usize>(arguments: [&str; N]) -> Result<Vec<u8>> {
    let output = Command::new("grim")
        .args(arguments)
        .output()
        .context("Could not launch grim. Install grim 1.5 or newer")?;
    ensure!(
        output.status.success(),
        "Screenshot failed (grim {}): {}",
        output.status,
        String::from_utf8_lossy(&output.stderr).trim()
    );
    Ok(output.stdout)
}

pub(crate) fn crop_png(png: &[u8], rect: [u32; 4]) -> Result<Vec<u8>> {
    encode_png(&crop(&decode(png, ImageFormat::Png)?, rect)?)
}

pub(crate) fn crop(image: &RgbaImage, [x, y, width, height]: [u32; 4]) -> Result<RgbaImage> {
    ensure!(
        width > 0
            && height > 0
            && x.checked_add(width)
                .is_some_and(|right| right <= image.width())
            && y.checked_add(height)
                .is_some_and(|bottom| bottom <= image.height()),
        "The selection is outside the captured image"
    );
    Ok(image.view(x, y, width, height).to_image())
}

fn decode(bytes: &[u8], format: ImageFormat) -> Result<RgbaImage> {
    let image = ImageReader::with_format(Cursor::new(bytes), format)
        .decode()
        .context("Could not decode the captured image")?;
    Ok(image.into_rgba8())
}

pub(crate) fn encode_png(image: &RgbaImage) -> Result<Vec<u8>> {
    encode_rgba_png(image.width(), image.height(), image.as_raw())
}

pub(crate) fn encode_rgba_png(width: u32, height: u32, pixels: &[u8]) -> Result<Vec<u8>> {
    let mut png = Vec::new();
    PngEncoder::new_with_quality(&mut png, CompressionType::Fast, FilterType::Adaptive)
        .write_image(pixels, width, height, ExtendedColorType::Rgba8)
        .context("Could not encode the screenshot as PNG")?;
    Ok(png)
}

pub(crate) fn check_png(png: &[u8]) -> Result<()> {
    ImageReader::with_format(Cursor::new(png), ImageFormat::Png)
        .into_dimensions()
        .context("The screenshot is not a valid PNG")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    #[test]
    fn crops_to_exact_source_pixels_and_checks_bounds() -> Result<()> {
        let source = RgbaImage::from_fn(4, 3, |x, y| Rgba([x as u8, y as u8, 17, 128]));
        let png = encode_png(&source)?;
        let cropped = decode(&crop_png(&png, [2, 1, 2, 2])?, ImageFormat::Png)?;
        assert_eq!(cropped.dimensions(), (2, 2));
        assert_eq!(*cropped.get_pixel(1, 1), Rgba([3, 2, 17, 128]));
        assert!(crop_png(&png, [1, 0, u32::MAX, 2]).is_err());
        assert!(crop_png(&png, [1, 0, 0, 2]).is_err());
        assert!(crop_png(b"not an image", [1, 0, 2, 2]).is_err());
        Ok(())
    }
}
