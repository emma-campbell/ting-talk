# Runs once at power-on/hard reset, before code.py, and decides what the Ting
# looks like over USB. A bad edit drops the board into safe mode; CIRCUITPY
# still mounts and boot_out.txt has the error.
#
# Audio and the push-to-talk signal both leave through the coiled cable, so
# USB is only power, the serial console, and the CIRCUITPY drive.

import usb_hid
import usb_midi

usb_midi.disable()
usb_hid.disable()
