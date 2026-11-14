# EP-2350 as a push-to-talk mic over the coiled cable. While the handle is in,
# the mic is live on the line-out with a quiet pilot tone mixed in; the Mac app
# detects the pilot and toggles Raycast dictation. The pilot is a level, not an
# edge, so the app always knows the handle state and can't drift out of sync.

import array
import os
import time

import analogio
import audiobusio
import audiocore
import audiofilters
import audioi2sin
import audiomixer
import board
import digitalio
import supervisor
import synthio

import adafruit_nau88l21
from talk import TalkWindow

SAMPLE_RATE = 48000  # the rate the NAU88L21 clock setup is tested at
MIC_GAIN_DB = 24  # codec analog gain, -1..36
PRE_GAIN_DB = 4.0  # digital makeup gain after the high-pass
HPF_HZ = 100  # cuts handling rumble, leaves speech alone
RELEASE_TAIL = 0.3  # keep the mic open briefly after release so last words land (D1)

PILOT_HZ = 18000  # above speech; must match the Mac app
PILOT_LEVEL = 0.1  # mixer level of the pilot, relative to full-scale voice

# D5: power off after this long without a squeeze, on batteries only.
# Set in CIRCUITPY/settings.toml (the TingTalk app writes it); 0 = never.
SLEEP_AFTER = float(os.getenv("TING_SLEEP_AFTER", 600))


def output(pin, value=False):
    io = digitalio.DigitalInOut(pin)
    io.switch_to_output(value=value)
    return io


def pulled_up(pin):
    io = digitalio.DigitalInOut(pin)
    io.switch_to_input(pull=digitalio.Pull.UP)
    return io


def sine_table(size=256):
    import math

    return array.array(
        "h", [int(32767 * math.sin(2 * math.pi * i / size)) for i in range(size)]
    )


def start_audio():
    """Wire mic → filters → mixer (+ pilot synth) → line-out. Returns (mixer, capture, synth, pilot)."""
    # The codec slaves to the I2S bit clock, and only I2SOut generates it, so
    # something must be playing before configure_clocks(). Silence will do;
    # the mixer replaces it below.
    silence = audiocore.RawSample(
        array.array("h", [0] * 256), sample_rate=SAMPLE_RATE, channel_count=1
    )
    line_out = audiobusio.I2SOut(board.I2S_BIT_CLOCK, board.I2S_WS, board.I2S_DOUT)
    line_out.play(silence, loop=True)

    codec = adafruit_nau88l21.NAU88L21(board.I2C())
    codec.configure_clocks()
    codec.headphone_output = True  # powers the coiled-cable line-out
    codec.configure_microphone_input(gain_db=MIC_GAIN_DB)

    capture = audioi2sin.I2SIn(
        board.I2S_BIT_CLOCK,
        board.I2S_WS,
        board.I2S_DIN,
        sample_rate=SAMPLE_RATE,
        bit_depth=16,
        mono=True,
        external_clock=True,
        left_justified=False,
    )

    fmt = dict(
        buffer_size=1024,
        sample_rate=SAMPLE_RATE,
        bits_per_sample=16,
        samples_signed=True,
        channel_count=1,
    )
    hpf = audiofilters.Filter(
        filter=synthio.Biquad(synthio.FilterMode.HIGH_PASS, frequency=HPF_HZ, Q=0.7),
        mix=1.0,
        **fmt,
    )
    gain = audiofilters.Distortion(
        pre_gain=PRE_GAIN_DB,
        drive=0.0,
        mode=audiofilters.DistortionMode.LOFI,
        soft_clip=True,
        mix=1.0,
        **fmt,
    )
    mixer = audiomixer.Mixer(voice_count=2, **fmt)
    synth = synthio.Synthesizer(sample_rate=SAMPLE_RATE, channel_count=1)
    pilot = synthio.Note(frequency=PILOT_HZ, waveform=sine_table())

    # Wire from the output backwards. I2SOut.play() knocks the external-clock
    # capture off its frame, and only a play() *on the mic* re-locks it, so
    # handing the capture to the filter must be the very last call.
    mixer.voice[0].level = 0.0
    mixer.voice[1].level = PILOT_LEVEL
    line_out.play(mixer)
    mixer.play(gain, voice=0, loop=True)
    mixer.play(synth, voice=1, loop=True)
    gain.play(hpf)
    hpf.play(capture)
    return mixer, capture, synth, pilot


def power_off(leds):
    """Drop POWER_HOLD; the handle is the power button, so a squeeze boots us
    again. Returns the claimed pin, held high again, only if something else
    (a USB charger) kept us powered; the caller keeps it so power stays held.

    Claim POWER_HOLD only here: CircuitPython drives it high at boot, and a
    claimed pin is reset when code.py reloads (e.g. on every file save),
    which powers the Ting off.
    """
    print("idle on battery: powering off")
    for led in leds:
        led.value = False
    hold = digitalio.DigitalInOut(board.POWER_HOLD)
    hold.switch_to_output(value=False)
    time.sleep(1)
    hold.value = True
    print("still powered; staying on")
    return hold


def main():
    hold = None
    status = output(board.LED_WHITE1, True)
    errors = output(board.LED_RED1)
    try:
        mixer, capture, synth, pilot = start_audio()
    except Exception as exc:
        print("startup failed:", exc)
        while True:
            errors.value = not errors.value
            time.sleep(0.15)

    volume = analogio.AnalogIn(board.VOLUME)
    # HANDLE_OUT reads high as soon as the handle starts moving in.
    handle = pulled_up(board.HANDLE_OUT)
    window = TalkWindow(tail=RELEASE_TAIL, sleep_after=SLEEP_AFTER, started=time.monotonic())
    held_was = None
    talking = False
    # D5: time from power-on to ready is most of the wake latency after sleep.
    print("ready", time.monotonic(), "s after boot; pilot", PILOT_HZ, "Hz, sleep after", SLEEP_AFTER, "s")

    while True:
        held = handle.value
        if held != held_was:
            print("handle", "held" if held else "released")
            held_was = held
        # The pilot spans exactly the open-mic window, release tail included,
        # so the app doesn't stop dictation before the last word arrives.
        if window.update(held, time.monotonic()) != talking:
            talking = not talking
            status.value = not talking  # LED off while talking, as a visible check
            if talking:
                synth.press(pilot)
            else:
                synth.release(pilot)
        mixer.voice[0].level = volume.value / 65535 if talking else 0.0
        if capture.overflow:
            print("capture overflow")
        now = time.monotonic()
        if hold is None and window.should_power_off(now, on_usb=supervisor.runtime.usb_connected):
            hold = power_off([status, errors])
            status.value = True
            window = TalkWindow(tail=RELEASE_TAIL, sleep_after=SLEEP_AFTER, started=now)
        time.sleep(0.02)


main()
