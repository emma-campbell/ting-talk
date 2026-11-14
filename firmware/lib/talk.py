"""When the Ting is "talking" (mic open, pilot on) and when it may sleep.

Pure logic so it runs under pytest on the Mac as well as on the device.
"""


class TalkWindow:
    def __init__(self, tail=0.3, sleep_after=600.0, started=0.0):
        self.tail = tail
        self.sleep_after = sleep_after
        self._open_until = float("-inf")
        self._last_talk = started

    def update(self, held, now):
        """Feed the handle state; return True while talking.

        The handle counts as held until the reading that shows it released,
        and the tail runs from that reading.
        """
        if held:
            self._open_until = float("inf")
        elif self._open_until == float("inf"):
            self._open_until = now + self.tail
        talking = now < self._open_until
        if talking:
            self._last_talk = now
        return talking

    def idle(self, now):
        """True once nobody has talked for `sleep_after` seconds (0 = never)."""
        if self.sleep_after <= 0 or now < self._open_until:
            return False
        last = max(self._last_talk, self._open_until)
        return now - last >= self.sleep_after

    def should_power_off(self, now, on_usb):
        """D5: power off when idle, but only on batteries."""
        return not on_usb and self.idle(now)
