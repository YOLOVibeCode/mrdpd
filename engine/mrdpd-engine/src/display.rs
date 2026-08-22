//! Frame buffer shared between `push_frame` (sync ABI) and IronRDP (async).

use std::num::{NonZeroU16, NonZeroUsize};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use bytes::Bytes;
use ironrdp_server::{
    BitmapUpdate, DesktopSize, DisplayUpdate, PixelFormat, RdpServerDisplay, RdpServerDisplayUpdates,
};
use tokio::sync::mpsc;

#[derive(Clone)]
pub struct SharedDisplay {
    size: Arc<Mutex<DesktopSize>>,
    tx: mpsc::UnboundedSender<BitmapUpdate>,
    rx: Arc<tokio::sync::Mutex<mpsc::UnboundedReceiver<BitmapUpdate>>>,
}

impl SharedDisplay {
    pub fn new(width: u16, height: u16) -> Self {
        let (tx, rx) = mpsc::unbounded_channel();
        Self {
            size: Arc::new(Mutex::new(DesktopSize { width, height })),
            tx,
            rx: Arc::new(tokio::sync::Mutex::new(rx)),
        }
    }

    pub fn push_bgra(&self, width: u16, height: u16, stride: usize, pixels: &[u8]) -> Result<(), i32> {
        let w = NonZeroU16::new(width).ok_or(1)?;
        let h = NonZeroU16::new(height).ok_or(1)?;
        let stride = NonZeroUsize::new(stride).ok_or(1)?;
        if let Ok(mut size) = self.size.lock() {
            *size = DesktopSize { width, height };
        }
        let update = BitmapUpdate {
            x: 0,
            y: 0,
            width: w,
            height: h,
            format: PixelFormat::BgrA32,
            data: Bytes::copy_from_slice(pixels),
            stride,
        };
        self.tx.send(update).map_err(|_| 7i32)?;
        Ok(())
    }
}

struct FrameUpdates {
    rx: Arc<tokio::sync::Mutex<mpsc::UnboundedReceiver<BitmapUpdate>>>,
}

#[async_trait]
impl RdpServerDisplayUpdates for FrameUpdates {
    async fn next_update(&mut self) -> anyhow::Result<Option<DisplayUpdate>> {
        let mut rx = self.rx.lock().await;
        Ok(rx.recv().await.map(DisplayUpdate::Bitmap))
    }
}

#[async_trait]
impl RdpServerDisplay for SharedDisplay {
    async fn size(&mut self) -> DesktopSize {
        self.size
            .lock()
            .map(|g| DesktopSize {
                width: g.width,
                height: g.height,
            })
            .unwrap_or(DesktopSize {
                width: 64,
                height: 64,
            })
    }

    async fn updates(&mut self) -> anyhow::Result<Box<dyn RdpServerDisplayUpdates>> {
        Ok(Box::new(FrameUpdates {
            rx: Arc::clone(&self.rx),
        }))
    }
}
