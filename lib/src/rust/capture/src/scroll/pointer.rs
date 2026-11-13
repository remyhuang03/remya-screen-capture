//! Wheel input for auto-scrolling, sent through the compositor's
//! `zwlr_virtual_pointer_v1` (supported by Hyprland and other wlroots-style
//! compositors).

use anyhow::{Context, Result, ensure};
use std::time::Instant;
use wayland_client::globals::{GlobalListContents, registry_queue_init};
use wayland_client::protocol::wl_output::{self, WlOutput};
use wayland_client::protocol::wl_pointer::{Axis, AxisSource};
use wayland_client::protocol::{wl_registry::WlRegistry, wl_seat::WlSeat};
use wayland_client::{Connection, Dispatch, EventQueue, QueueHandle, delegate_noop};
use wayland_protocols_wlr::virtual_pointer::v1::client::{
    zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1,
    zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1,
};

/// libinput reports 15 degrees, i.e. a value of 15, per wheel notch.
const NOTCH: f64 = 15.0;

pub(crate) struct VirtualPointer {
    connection: Connection,
    _queue: EventQueue<State>,
    pointer: ZwlrVirtualPointerV1,
    clock: Instant,
}

#[derive(Default)]
struct State {
    outputs: Vec<(WlOutput, String)>,
}

impl VirtualPointer {
    /// Opens a pointer whose absolute coordinates map onto output `name`.
    pub(crate) fn new(name: &str) -> Result<Self> {
        let connection =
            Connection::connect_to_env().context("Could not connect to the Wayland display")?;
        let (globals, mut queue) = registry_queue_init::<State>(&connection)
            .context("Could not read the Wayland globals")?;
        let qh = queue.handle();
        let manager: ZwlrVirtualPointerManagerV1 = globals
            .bind(&qh, 2..=2, ())
            .context("The compositor does not support virtual pointers, needed to scroll")?;
        let seat: WlSeat = globals.bind(&qh, 1..=1, ()).context("No Wayland seat")?;
        for global in globals.contents().clone_list() {
            if global.interface == "wl_output" && global.version >= 4 {
                // Kept alive by `State::outputs` once its name arrives.
                globals
                    .registry()
                    .bind::<WlOutput, _, _>(global.name, 4, &qh, ());
            }
        }
        let mut state = State::default();
        queue.roundtrip(&mut state)?;
        let output = state
            .outputs
            .iter()
            .find(|(_, output)| output == name)
            .map(|(output, _)| output)
            .with_context(|| format!("Display {name} is not available for scrolling"))?;
        let pointer =
            manager.create_virtual_pointer_with_output(Some(&seat), Some(output), &qh, ());
        connection.flush()?;
        Ok(Self {
            connection,
            _queue: queue,
            pointer,
            clock: Instant::now(),
        })
    }

    /// Moves the cursor to `(x, y)` within an output of `width` × `height`
    /// pixels, then turns the wheel by `notches` (positive scrolls down).
    pub(crate) fn scroll(&self, [x, y, width, height]: [u32; 4], notches: i32) -> Result<()> {
        ensure!(notches != 0, "Nothing to scroll");
        let time = self.clock.elapsed().as_millis() as u32;
        self.pointer.motion_absolute(time, x, y, width, height);
        self.pointer.frame();
        self.pointer.axis_source(AxisSource::Wheel);
        self.pointer
            .axis_discrete(time, Axis::VerticalScroll, NOTCH * notches as f64, notches);
        self.pointer.frame();
        self.connection
            .flush()
            .context("Could not send the scroll to the compositor")
    }
}

impl Drop for VirtualPointer {
    fn drop(&mut self) {
        self.pointer.destroy();
        let _ = self.connection.flush();
    }
}

impl Dispatch<WlOutput, ()> for State {
    fn event(
        state: &mut Self,
        output: &WlOutput,
        event: wl_output::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wl_output::Event::Name { name } = event {
            state.outputs.push((output.clone(), name));
        }
    }
}

impl Dispatch<WlRegistry, GlobalListContents> for State {
    fn event(
        _: &mut Self,
        _: &WlRegistry,
        _: <WlRegistry as wayland_client::Proxy>::Event,
        _: &GlobalListContents,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

delegate_noop!(State: ignore WlSeat);
delegate_noop!(State: ZwlrVirtualPointerManagerV1);
delegate_noop!(State: ZwlrVirtualPointerV1);
