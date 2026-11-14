# Regression bench (M12): run the real main() with scripted presses and a
# forced garbage collection, while recording the line-out on the Mac.
# Copy to CIRCUITPY, then from the REPL: exec(open("bench_gc.py").read())
# (Ctrl-C to stop). Every 1.0 s the handle and the middle button go down in the
# same tick and come up 0.5 s later; gc.collect() runs once at 5 s. Pass: both
# the 18 kHz and 17 kHz tones appear every second for the whole run. Before the
# _audio_chain fix in code.py, the line-out went silent at the first collection.
import gc
import time
import board
import code

start = time.monotonic()
collected = False

class Fake:
    def __init__(self, pin):
        self.pin = pin

    @property
    def value(self):
        global collected
        if not collected and time.monotonic() - start > 5:
            collected = True
            gc.collect()
            print("forced gc.collect at 5 s")
        down = (time.monotonic() - start) % 1.0 < 0.5
        if self.pin is board.HANDLE_OUT:
            return down          # HANDLE_OUT reads high while held
        if self.pin is board.BUTTON_MIDDLE:
            return not down      # buttons read low while pressed
        return True              # other buttons: released

code.pulled_up = Fake
print("bench_real start")
code.main()
