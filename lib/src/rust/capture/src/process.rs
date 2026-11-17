use std::{
    io::{self, Read, Write},
    os::{fd::OwnedFd, unix::net::UnixStream},
    process::{Command, Output, Stdio},
    thread,
    time::{Duration, Instant},
};

pub(crate) fn capture(mut command: Command, timeout: Duration) -> io::Result<Output> {
    let (stdout, child_stdout) = pipe()?;
    let (stderr, child_stderr) = pipe()?;
    command
        .stdin(Stdio::null())
        .stdout(child_stdout)
        .stderr(child_stderr);
    run(command, None, Some(stdout), Some(stderr), timeout)
}

pub(crate) fn send(mut command: Command, data: &[u8], timeout: Duration) -> io::Result<Output> {
    let (stdin, child_stdin) = pipe()?;
    command.stdin(child_stdin).stdout(Stdio::null());
    // wl-copy's background clipboard owner can keep stderr open.
    run(command, Some((stdin, data)), None, None, timeout)
}

fn pipe() -> io::Result<(UnixStream, Stdio)> {
    let (local, remote) = UnixStream::pair()?;
    local.set_nonblocking(true)?;
    Ok((local, Stdio::from(OwnedFd::from(remote))))
}

fn run(
    mut command: Command,
    mut input: Option<(UnixStream, &[u8])>,
    mut output: Option<UnixStream>,
    mut errors: Option<UnixStream>,
    timeout: Duration,
) -> io::Result<Output> {
    let deadline = Instant::now() + timeout;
    let mut child = command.spawn()?;
    drop(command);

    let result = (|| {
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();
        let mut buffer = [0; 65536];
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(io::ErrorKind::TimedOut.into());
            }

            let mut progress = false;
            if let Some((stream, data)) = &mut input {
                match stream.write(data) {
                    Ok(written) => {
                        *data = &data[written..];
                        progress |= written != 0;
                    }
                    Err(error) if retryable(&error) => {}
                    Err(error) => return Err(error),
                }
                if data.is_empty() {
                    input = None;
                }
            }
            let status = child.try_wait()?;
            progress |= read(&mut output, &mut stdout, &mut buffer)?;
            progress |= read(&mut errors, &mut stderr, &mut buffer)?;
            if let Some(status) = status
                && !progress
            {
                if status.success() && input.is_some() {
                    return Err(io::ErrorKind::BrokenPipe.into());
                }
                return Ok(Output {
                    status,
                    stdout,
                    stderr,
                });
            }
            if !progress {
                thread::sleep(remaining.min(Duration::from_millis(5)));
            }
        }
    })();

    if result.is_err() {
        let _ = child.kill();
        let _ = child.wait();
    }
    result
}

fn read(
    stream: &mut Option<UnixStream>,
    bytes: &mut Vec<u8>,
    buffer: &mut [u8],
) -> io::Result<bool> {
    let Some(socket) = stream else {
        return Ok(false);
    };
    match socket.read(buffer) {
        Ok(0) => {
            *stream = None;
            Ok(false)
        }
        Ok(count) => {
            bytes.extend_from_slice(&buffer[..count]);
            Ok(true)
        }
        Err(error) if retryable(&error) => Ok(false),
        Err(error) => Err(error),
    }
}

fn retryable(error: &io::Error) -> bool {
    matches!(
        error.kind(),
        io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn captures_output_larger_than_the_pipe() -> io::Result<()> {
        let mut command = Command::new("sh");
        command.args([
            "-c",
            "head -c 1048576 /dev/zero; printf diagnostic >&2; exit 4",
        ]);
        let output = capture(command, Duration::from_secs(2))?;
        assert_eq!(output.status.code(), Some(4));
        assert_eq!(output.stdout.len(), 1048576);
        assert_eq!(output.stderr, b"diagnostic");
        Ok(())
    }

    #[test]
    fn stuck_input_times_out_and_reaps_the_child() -> io::Result<()> {
        let directory = tempfile::tempdir()?;
        let pid_file = directory.path().join("pid");
        let mut command = Command::new("sh");
        command
            .args(["-c", "echo $$ > \"$1\"; exec sleep 60", "fixture"])
            .arg(&pid_file);
        let data = vec![0; 1024 * 1024];
        let error = send(command, &data, Duration::from_millis(500)).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::TimedOut);
        let pid = std::fs::read_to_string(pid_file)?;
        assert!(!std::path::Path::new("/proc").join(pid.trim()).exists());
        Ok(())
    }
}
