use anyhow::{Context, Result, ensure};
use std::process::Command;
use std::sync::Mutex;
use std::thread::{self, JoinHandle};

use crate::api::{StartupCapture, StartupFrame};

static PREFETCH: Mutex<Option<JoinHandle<Result<Option<StartupCapture>>>>> = Mutex::new(None);

// Called before GTK/Flutter startup; the runner already holds the capture lock.
#[unsafe(no_mangle)]
pub extern "C" fn remya_prefetch_capture() {
    let mut pending = PREFETCH.lock().unwrap();
    if pending.is_none() {
        *pending = Some(thread::spawn(capture));
    }
}

pub(crate) fn take() -> Option<StartupCapture> {
    let pending = PREFETCH.lock().ok()?.take()?;
    match pending.join() {
        Ok(Ok(snapshot)) => snapshot,
        _ => None,
    }
}

fn hyprctl(arguments: &[&str]) -> Result<String> {
    let output = Command::new("hyprctl").args(arguments).output()?;
    ensure!(output.status.success(), "Could not read Hyprland state");
    Ok(String::from_utf8(output.stdout)?)
}

fn capture() -> Result<Option<StartupCapture>> {
    thread::scope(|scope| {
        let monitors = scope.spawn(|| hyprctl(&["-j", "monitors"]));
        let windows = scope.spawn(|| hyprctl(&["-j", "clients"]));
        let cursor = scope.spawn(|| hyprctl(&["-j", "cursorpos"]));
        // shortcut: shader/software-cursor changes use the existing guarded
        // Dart path; move that suspension here if this configuration needs prefetch.
        let safe = hyprctl(&[
            "repl",
            "return hl.get_config('decoration.screen_shader') == '' and hl.get_config('cursor.no_hardware_cursors') == 0 and 'safe' or 'fallback'",
        ])?;
        if safe.trim() != "safe" {
            return Ok(None);
        }
        let monitors = monitors.join().unwrap()?;
        let names = output_names(&monitors)?;
        let frames = names
            .into_iter()
            .map(|name| {
                scope.spawn(move || {
                    Ok(StartupFrame {
                        png: crate::capture::output_png(&name)?,
                        name,
                    })
                })
            })
            .collect::<Vec<_>>();
        let frames = frames
            .into_iter()
            .map(|frame| frame.join().unwrap())
            .collect::<Result<_>>()?;
        Ok(Some(StartupCapture {
            monitors,
            windows: windows.join().unwrap()?,
            cursor: cursor.join().unwrap()?,
            frames,
        }))
    })
}

fn output_names(monitors: &str) -> Result<Vec<String>> {
    let monitors: serde_json::Value = serde_json::from_str(monitors)?;
    monitors
        .as_array()
        .context("Invalid Hyprland monitors")?
        .iter()
        .filter(|monitor| monitor["disabled"] != true && monitor["mirrorOf"] == "none")
        .map(|monitor| {
            Ok(monitor["name"]
                .as_str()
                .filter(|name| !name.is_empty())
                .context("Missing output name")?
                .to_owned())
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn consumes_snapshot_once_and_falls_back_after_failure() {
        *PREFETCH.lock().unwrap() = Some(thread::spawn(|| {
            Ok(Some(StartupCapture {
                monitors: "monitors".into(),
                windows: "windows".into(),
                cursor: "cursor".into(),
                frames: vec![StartupFrame {
                    name: "DP-1".into(),
                    png: vec![1, 2, 3],
                }],
            }))
        }));
        let snapshot = take().unwrap();
        assert_eq!(snapshot.frames[0].name, "DP-1");
        assert_eq!(snapshot.frames[0].png, [1, 2, 3]);
        assert!(take().is_none());
        *PREFETCH.lock().unwrap() = Some(thread::spawn(|| anyhow::bail!("capture failed")));
        assert!(take().is_none());
    }

    #[test]
    fn uses_only_named_active_non_mirrored_outputs() -> Result<()> {
        assert_eq!(
            output_names(
                r#"[{"name":"DP-1","mirrorOf":"none"},{"name":"DP-2","disabled":true,"mirrorOf":"none"},{"name":"DP-3","mirrorOf":"DP-1"}]"#
            )?,
            ["DP-1"]
        );
        assert!(output_names(r#"[{"mirrorOf":"none"}]"#).is_err());
        assert!(output_names("{}").is_err());
        assert!(output_names("bad json").is_err());
        Ok(())
    }
}
