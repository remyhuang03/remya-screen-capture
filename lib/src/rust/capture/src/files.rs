use anyhow::{Context, Result, bail, ensure};
use std::fs;
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;
use tempfile::NamedTempFile;

use crate::capture::check_png;

pub(crate) fn copy_png(png: &[u8]) -> Result<()> {
    check_png(png)?;
    copy(png, "image/png")
}

pub(crate) fn copy_text(text: &str) -> Result<()> {
    ensure!(!text.is_empty(), "There is no text to copy");
    copy(text.as_bytes(), "text/plain;charset=utf-8")
}

fn copy(data: &[u8], mime: &str) -> Result<()> {
    let mut command = Command::new("wl-copy");
    command.args(["--type", mime]);
    let result = crate::process::send(command, data, Duration::from_secs(3)).map_err(|error| {
        if error.kind() == ErrorKind::NotFound {
            anyhow::anyhow!(
                "Could not launch wl-copy. Install wl-clipboard to copy to the clipboard"
            )
        } else {
            anyhow::anyhow!("Could not copy to the Wayland clipboard: {error}")
        }
    })?;
    ensure!(
        result.status.success(),
        "Could not copy to the Wayland clipboard (wl-copy {})",
        result.status
    );
    Ok(())
}

pub(crate) fn save_png(png: &[u8], path: &str, replace: bool, unique: bool) -> Result<String> {
    check_png(png)?;
    ensure!(!(replace && unique), "Choose one file replacement policy");
    let path = Path::new(path);
    ensure!(
        path.is_absolute() && path.file_name().is_some(),
        "Select an absolute path with a file name"
    );
    let parent = path
        .parent()
        .context("Missing screenshot destination folder")?;
    if unique {
        fs::create_dir_all(parent).context("Could not create the screenshot folder")?;
    }

    let mut temp = NamedTempFile::new_in(parent).context("Could not open the screenshot folder")?;
    temp.write_all(png)
        .context("Could not write the screenshot")?;
    temp.as_file()
        .sync_all()
        .context("Could not finish writing the screenshot")?;
    if replace {
        temp.persist(path)
            .context("Could not replace the screenshot")?;
        return Ok(path.to_string_lossy().into_owned());
    }

    for index in 0..10_000 {
        let target = if index == 0 {
            path.to_owned()
        } else {
            numbered_name(path, index)
        };
        match temp.persist_noclobber(&target) {
            Ok(_) => return Ok(target.to_string_lossy().into_owned()),
            Err(error) if unique && error.error.kind() == ErrorKind::AlreadyExists => {
                temp = error.file;
            }
            Err(error) => return Err(error).context("Could not save the screenshot"),
        }
    }
    bail!("Could not find an unused screenshot file name")
}

fn numbered_name(path: &Path, index: u32) -> PathBuf {
    let mut name = path.file_stem().unwrap_or_default().to_owned();
    name.push(format!(" ({index})"));
    if let Some(extension) = path.extension() {
        name.push(".");
        name.push(extension);
    }
    path.with_file_name(name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    #[test]
    fn atomic_save_preserves_existing_files_until_replacement_is_requested() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("Pictures/Capture.png");
        let path = path.to_str().unwrap();
        let old = crate::capture::encode_png(&RgbaImage::from_pixel(2, 2, Rgba([0, 0, 0, 255])))?;
        let new = crate::capture::encode_png(&RgbaImage::from_pixel(2, 2, Rgba([255, 0, 0, 255])))?;
        assert_eq!(save_png(&old, path, false, true)?, path);
        assert!(save_png(&new, path, false, false).is_err());
        assert_eq!(fs::read(path)?, old);
        let second = save_png(&new, path, false, true)?;
        assert!(second.ends_with("Capture (1).png"));
        assert_eq!(fs::read(second)?, new);
        assert_eq!(save_png(&new, path, true, false)?, path);
        assert_eq!(fs::read(path)?, new);
        Ok(())
    }
}
