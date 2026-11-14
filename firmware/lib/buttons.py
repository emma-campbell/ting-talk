"""When a side button's tone plays (D7).

Pure logic so it runs under pytest on the Mac as well as on the device.
"""


class ButtonTone:
    """The tone plays while the button is held, for at least `min_on` seconds
    so a quick tap is long enough for the Mac to detect. After it stops, a new
    press is ignored for `gap` seconds, so a release bounce can't start a
    second tone."""

    def __init__(self, min_on=0.12, gap=0.08):
        self.min_on = min_on
        self.gap = gap
        self._on = False
        self._started = 0.0
        self._ready_at = float("-inf")

    def update(self, pressed, now):
        """Feed the button state; return True while the tone should play."""
        if not self._on:
            if pressed and now >= self._ready_at:
                self._on = True
                self._started = now
        elif not pressed and now - self._started >= self.min_on:
            self._on = False
            self._ready_at = now + self.gap
        return self._on
