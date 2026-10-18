import os

class RGBDriver:
    """TrimUI handhelds whose RGB LEDs hang off the gamepad MCU (Brick Hammer
    Pro U).  The kernel serdev driver takes a vendor-style frame -- 24 pixels
    of 32-bit little-endian XRGB -- on /sys/class/led_anim/frame and streams
    it to the MCU; a frame is only shown while frames keep coming, which the
    daemon's fixed tick provides."""

    FRAME_LEDS = 24

    def __init__(self, extra: dict) -> None:
        with open('/sys/class/led_anim/max_scale', 'w') as f:
            f.write(str(extra.get('max_scale', 255)))
        self.rgb_sink = os.open('/sys/class/led_anim/frame', os.O_WRONLY)

    # expects a list of rgb values [255,0,0, ... ]
    def render(self, rgb_data: list[int]) -> bytes:
        out = bytearray(self.FRAME_LEDS * 4)
        for i in range(min(len(rgb_data) // 3, self.FRAME_LEDS)):
            out[4 * i + 0] = rgb_data[3 * i + 2]   # B
            out[4 * i + 1] = rgb_data[3 * i + 1]   # G
            out[4 * i + 2] = rgb_data[3 * i + 0]   # R
        return bytes(out)

    def write(self, led_data: bytes):
        os.write(self.rgb_sink, led_data)

    def close(self) -> None:
        os.close(self.rgb_sink)
