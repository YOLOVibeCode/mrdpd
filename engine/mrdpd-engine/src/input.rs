//! FastPath input → ABI callbacks. No IronRDP types leak out of this crate.

use ironrdp_server::{
    ConnectionHandler, KeyboardEvent, MouseEvent, PostConnectionAction, RdpServerInputHandler,
};

use crate::{fire_connected, fire_disconnected, fire_key, fire_mouse, MrdpdCallbacks, MrdpdKeyEvent, MrdpdMouseEvent};

pub struct InputForwarder {
    cbs: MrdpdCallbacks,
    x: i32,
    y: i32,
    buttons: u32,
}

impl InputForwarder {
    pub fn new(cbs: MrdpdCallbacks) -> Self {
        Self {
            cbs,
            x: 0,
            y: 0,
            buttons: 0,
        }
    }

    fn emit_mouse(&self, wheel: i16) {
        fire_mouse(
            &self.cbs,
            MrdpdMouseEvent {
                x: self.x,
                y: self.y,
                buttons: self.buttons,
                wheel,
            },
        );
    }
}

impl RdpServerInputHandler for InputForwarder {
    fn keyboard(&mut self, event: KeyboardEvent) {
        let (scancode, extended, pressed) = match event {
            KeyboardEvent::Pressed { code, extended } => (u16::from(code), u8::from(extended), 1u8),
            KeyboardEvent::Released { code, extended } => (u16::from(code), u8::from(extended), 0u8),
            KeyboardEvent::UnicodePressed(_)
            | KeyboardEvent::UnicodeReleased(_)
            | KeyboardEvent::Synchronize(_) => return,
        };
        fire_key(
            &self.cbs,
            MrdpdKeyEvent {
                scancode,
                extended,
                pressed,
            },
        );
    }

    fn mouse(&mut self, event: MouseEvent) {
        match event {
            MouseEvent::Move { x, y } => {
                self.x = i32::from(x);
                self.y = i32::from(y);
                self.emit_mouse(0);
            }
            MouseEvent::LeftPressed => {
                self.buttons |= 1;
                self.emit_mouse(0);
            }
            MouseEvent::LeftReleased => {
                self.buttons &= !1;
                self.emit_mouse(0);
            }
            MouseEvent::RightPressed => {
                self.buttons |= 2;
                self.emit_mouse(0);
            }
            MouseEvent::RightReleased => {
                self.buttons &= !2;
                self.emit_mouse(0);
            }
            MouseEvent::MiddlePressed => {
                self.buttons |= 4;
                self.emit_mouse(0);
            }
            MouseEvent::MiddleReleased => {
                self.buttons &= !4;
                self.emit_mouse(0);
            }
            MouseEvent::Button4Pressed | MouseEvent::Button5Pressed => self.emit_mouse(0),
            MouseEvent::Button4Released | MouseEvent::Button5Released => self.emit_mouse(0),
            MouseEvent::VerticalScroll { value } => self.emit_mouse(value),
            MouseEvent::Scroll { y, .. } => {
                let wheel = i16::try_from(y).unwrap_or(0);
                self.emit_mouse(wheel);
            }
            MouseEvent::RelMove { x, y } => {
                self.x = self.x.saturating_add(x);
                self.y = self.y.saturating_add(y);
                self.emit_mouse(0);
            }
        }
    }
}

pub struct ConnForwarder {
    cbs: MrdpdCallbacks,
}

impl ConnForwarder {
    pub fn new(cbs: MrdpdCallbacks) -> Self {
        Self { cbs }
    }
}

impl ConnectionHandler for ConnForwarder {
    fn on_accept(&mut self, _peer: std::net::SocketAddr) -> bool {
        fire_connected(&self.cbs);
        true
    }

    fn on_disconnected(
        &mut self,
        _peer: std::net::SocketAddr,
        _duration: core::time::Duration,
        _error: Option<&anyhow::Error>,
    ) -> PostConnectionAction {
        fire_disconnected(&self.cbs, 0);
        PostConnectionAction::Continue
    }
}
