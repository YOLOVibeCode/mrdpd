//! 1080p labeled quadrants (T1-GFX-01 M2). Same layout as Swift `SyntheticFrameSource.pattern1080p`.
//! Not a C ABI symbol (ISP: v1 stays start/stop/push_frame).

pub const WIDTH: u32 = 1920;
pub const HEIGHT: u32 = 1080;
pub const STRIDE: u32 = WIDTH * 4;

/// Packed BGRA: red / green on top, blue / white on bottom (scaled 2×2 fixture).
pub fn bgra_1080p_quadrants() -> Vec<u8> {
    let mut pixels = vec![0u8; (STRIDE * HEIGHT) as usize];
    let mid_x = WIDTH / 2;
    let mid_y = HEIGHT / 2;
    for y in 0..HEIGHT {
        let top = y < mid_y;
        for x in 0..WIDTH {
            let color: [u8; 4] = if top {
                if x < mid_x {
                    [0x00, 0x00, 0xFF, 0xFF]
                } else {
                    [0x00, 0xFF, 0x00, 0xFF]
                }
            } else if x < mid_x {
                [0xFF, 0x00, 0x00, 0xFF]
            } else {
                [0xFF, 0xFF, 0xFF, 0xFF]
            };
            let i = (y * STRIDE + x * 4) as usize;
            pixels[i..i + 4].copy_from_slice(&color);
        }
    }
    pixels
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pixel(px: &[u8], x: u32, y: u32) -> [u8; 4] {
        let i = (y * STRIDE + x * 4) as usize;
        [px[i], px[i + 1], px[i + 2], px[i + 3]]
    }

    #[test]
    fn t1_gfx_01_1080p_quadrants_match_scaled_2x2() {
        let px = bgra_1080p_quadrants();
        assert_eq!(px.len(), (STRIDE * HEIGHT) as usize, "T1-GFX-01: packed 1920×1080 BGRA");
        if px.len() != (STRIDE * HEIGHT) as usize {
            return;
        }
        assert_eq!(pixel(&px, 480, 270), [0x00, 0x00, 0xFF, 0xFF], "top-left red");
        assert_eq!(pixel(&px, 1440, 270), [0x00, 0xFF, 0x00, 0xFF], "top-right green");
        assert_eq!(pixel(&px, 480, 810), [0xFF, 0x00, 0x00, 0xFF], "bottom-left blue");
        assert_eq!(pixel(&px, 1440, 810), [0xFF, 0xFF, 0xFF, 0xFF], "bottom-right white");
    }
}
