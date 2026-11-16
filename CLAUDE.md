# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A teenage engineering EP-2350 (FX MIC / "Ting") turned into a push-to-talk mic for whichever dictation tool the user picks. **The requirements live in `docs/requirements.md`, and work is test-first against them.**

It works over the **coiled cable only**. The Ting runs our CircuitPython firmware (`firmware/`), which puts the mic on the 3.5 mm line-out, plus an **18 kHz pilot tone** while the handle is in. The cable goes into an audio input (the CalDigit TS3's audio-in). The Swift menu-bar app `TingTalk` (`app/`) detects the pilot and fires the dictation trigger. USB-C is only for development and for changing device settings, and the Ting runs on 2 × AAA otherwise. The current state (verified end to end with Raycast) and what's still open are in `docs/manual-checks.md`.

Two earlier approaches were built, then dropped. Their lessons are in the gotchas below:
- A one-cable USB version, where the Ting acted as a USB mic and HID keyboard that double-tapped Command. It was dropped because the USB-C port sits under the lid.
- A Mac daemon for the **stock** TE firmware that polled `ui.sw(4)` over its MicroPython REPL.

## Commands

Python 3.13 and `uv` are only used to test the firmware's pure logic; the app is a Swift package.

```sh
firmware/install.sh  # copy firmware onto a mounted CIRCUITPY (code.py auto-reloads)
uv run pytest        # tests; firmware/lib is on the path, so device-side pure logic is testable
uv run pytest tests/test_talk.py::test_talking_continues_through_the_release_tail
cd app && swift test # Mac app logic (TalkCore): pilot detector against tests/fixtures + synthetic signals
cd app && swift test --filter whiteNoise
cd app && swift run TingTalk   # run the menu-bar app; its diagnostics print as [TingTalk] ...
scripts/build-app.sh 0.1.0 1   # Apple silicon, ad-hoc-signed dist/TingTalk.app + dist/TingTalk.zip
SIGN_IDENTITY="Apple Development: Emma Campbell (ML66NNUUN4)" scripts/build-app.sh  # local: permissions survive rebuilds
scripts/check-app.sh           # verify the bundle: Info.plist keys, arm64, minos 14, hardened runtime, mic entitlement
```

CI (`.github/workflows/ci.yml`) runs pytest and `swift test` on every PR and push to `main`, and attaches a built `TingTalk.zip` to the run. Releases are manual only: run `release.yml` from the Actions tab or with `gh workflow run release.yml -f version=0.1.0`. It refuses anything but `main`, a malformed version, or an existing release, then tests, builds, checks, and creates the `v<version>` tag and GitHub Release together. The app is ad-hoc signed, not notarized, so a downloaded copy needs right-click → Open the first time. The bundle (`app/Resources/Info.plist`, `TingTalk.entitlements`) has its own ID, `dev.emmacampbell.TingTalk`, so macOS grants permissions to it rather than to a terminal.

Keep device-side logic that needs testing as pure modules in `firmware/lib/` (like `talk.py`). Don't put `firmware/` itself on the path, because `firmware/code.py` shadows the stdlib `code` module and breaks pytest.

There's no linter or formatter set up yet. To watch the firmware's log, open `/dev/cu.usbmodem*` at 115200 and only read, since writing Ctrl-C stops `code.py`. Ctrl-D restarts it.

## Architecture

- `firmware/boot.py` runs only on a **hard** reset. It disables HID and MIDI, which leaves USB as just serial plus CIRCUITPY.
- `firmware/code.py` wires the audio chain: NAU88L21 codec → I2S capture → 100 Hz high-pass → gain → mixer (voice plus a `synthio` pilot) → I2SOut → line-out (`codec.headphone_output = True`). The codec locks to the bit clock from I2SOut, so I2SOut must already be playing before `configure_clocks()`. **Wire from the output backwards, with `hpf.play(capture)` as the very last call**, because any I2SOut `play()` knocks the capture off its frame. The main loop polls `board.HANDLE_OUT` (high once the handle moves in) through `TalkWindow`.
- `firmware/lib/talk.py` (`TalkWindow`) is pure, tested logic. The handle counts as held until a reading shows it released, and the talk window then runs for a 0.3 s tail. The pilot and the open mic both span exactly that window. `should_power_off()` drives sleep: on battery only (`supervisor.runtime.usb_connected` is false), after `TING_SLEEP_AFTER` seconds from `settings.toml` (default 600, 0 = never), `code.py` drops `POWER_HOLD`.
- **Measured 2026-11-14 through the CalDigit audio-in:** the pilot (18 kHz, mixer level 0.1) arrives about 40 dB above the noise floor, and no voice leaks while the mic is closed.
- `app/` (Swift package `TingTalk`) contains two targets. `TalkCore` is pure and tested: `PilotDetector` requires the pilot bin to be loud enough, 12 dB above four neighbour bins, and steady for 4 hops. `TriggerController` turns talking state into `KeyEvent`s and supports toggle or hold mode with a 0.4 s minimum gap between toggles. Deferred toggles come back via `nextDeadline`, and `stop()` handles pause, lost input, and quit. `TriggerPreset` lists the preset tools, and `ShortcutRecorder` turns key presses in Settings into a custom trigger, which is persisted as JSON. `DeviceSettings` reads and rewrites `TING_SLEEP_AFTER` in the Ting's `settings.toml`, keeping other lines intact. `InputChoice` picks the input to listen on: the saved one or, by default, the first named "CalDigit". It never falls back to another device. `TingTalk` is the menu-bar shell with a Settings window. `PilotMonitor` drives AVAudioEngine on the chosen input. `TingDevice` finds the Ting's CIRCUITPY drive (by `boot_out.txt`) to write settings. The cable only carries signal from the Ting, so settings can only change over USB. and `KeySender` posts CGEvents (modifiers as `flagsChanged`), which needs Accessibility permission. Diagnostics go to stderr as `[TingTalk] ...`.
- **Don't observe `AVAudioEngineConfigurationChange` to detect a lost input.** Selecting the device with `kAudioOutputUnitProperty_CurrentDevice` posts one, which caused an endless reconnect loop. A 1 s watchdog checks that the device is present and that buffers are still arriving.
- **Permissions belong to the signature.** An ad-hoc-signed app is a different app to macOS after every rebuild, so Accessibility has to be granted again each time. A stale grant from an older build can stay in the list and look switched on while doing nothing. Sign local builds with your Apple Development certificate (Personal Team `DC9YL28P72`, expires 2026-12-15, renewed by Xcode) and grants stick. To start fresh: `tccutil reset Accessibility dev.emmacampbell.TingTalk` (run it while the app is running, or it may report "no such bundle identifier"). Releases stay ad-hoc until there's a Developer ID, which needs the paid program.
- **The first-run window needs `orderFrontRegardless()`.** A menu-bar app launched while you're in another app isn't allowed to take focus, so `makeKeyAndOrderFront` alone leaves it hidden behind everything.
- An orange mic indicator that stays on while TingTalk is paused is usually System Settings → Sound, whose input meter also captures. CoreAudio's process list (`kAudioProcessPropertyIsRunningInput`) shows which process is actually capturing.
- The `firmware/lib/` Adafruit libraries (`adafruit_nau88l21`, `adafruit_bus_device`, `adafruit_register`) are vendored and MIT-licensed. The audio setup follows JR-One-Yard/ep-2350-usb-mic, which has no license, so we didn't copy its code.
- In the old USB version, `usb_hid.enable()` had to come after `usb_audio.enable()`, because in CircuitPython 10.3.2 enabling audio silently drops any HID devices enabled before it.

## Device facts and gotchas

- **Power:** the handle is the power button. USB power alone doesn't keep the Ting on: it stays on only while CircuitPython drives `POWER_HOLD` high, which it does at boot. A software reset (`microcontroller.reset()`) can leave it off, so squeeze the handle to bring it back.
- **Keep every audio object referenced** (`_audio_chain` in `code.py`). The audio hardware streams through objects that Python may hold only as locals in `start_audio()`. When the garbage collector frees one, the line-out goes silent for good with no error while the main loop carries on. It looked like a hardware or timing bug: it was intermittent, and adding diagnostics "fixed" it because they held a reference. `firmware/bench_gc.py` forces a collection to check this (M12).
- **Never claim `POWER_HOLD` in `code.py` except at the moment of powering off.** A claimed pin is reset whenever `code.py` reloads, and it reloads on every file write to CIRCUITPY, including macOS writing its metadata on mount. That reset powers the Ting off. If a bad build does this, hold the handle in (it keeps power) while copying a fix over.
- **With batteries in, unplugging USB doesn't restart the Ting.** Plugging USB back in while it's still running can leave CIRCUITPY **write-protected to the host** ("Media Read-Only: Yes"), while the filesystem checks clean. Restart it (the small button above the USB-C port is reset, or `microcontroller.reset()`, then squeeze) and it comes back writable. `storage.erase_filesystem()` also fixes it but isn't needed.
- **Opening the serial REPL (Ctrl-C) stops `code.py`.** The LEDs go dark and the mic stops. Send Ctrl-D to restart it. To just watch the log, open the port and only read.
- **Update/bootloader mode:** hold the handle in and double-click the small button above the USB-C port. `FX MIC BOOT` mounts, and you drop a `.uf2` on it. Keep holding the handle until it remounts.
- **Rollback to stock:** flash `~/hardware-firmware/stock-1.1.2/ep-2350_fx_mic_firmware_1_1_2.uf2`. Use the **fx_mic** file, not the ting one. CircuitPython is `~/hardware-firmware/circuitpython/circuitpython-10.3.2.uf2`. The original 1.0.9 isn't downloadable. Its `/rom/main.py` and README are backed up in `~/hardware-firmware/backup-stock-1.0.9/`.
- Use a data-capable USB-C cable, since a charge-only cable shows nothing at all. The port is under the lower lid.
- CircuitPython pin names: `HANDLE_IN` (seated, low when squeezed), `HANDLE_OUT` (moved, high when squeezed), `HANDLE_POSITION` (pot), `BUTTON_TOP/MIDDLE/BOTTOM` (pull-up, active low; on our FX MIC they're orange, white, and gray, and TE's readme colours describe the Ting variant, so code names buttons by position), `VOLUME`, `POWER_HOLD`, `LED_WHITE1-4`, `LED_RED1-4`, and the `I2S_*` pins.

### Stock firmware (only relevant if rolled back)

- MicroPython. The REPL is on the USB serial port with `ui` imported. `ui.sw(4)` is the handle (1 = held), `ui.handle()` gives travel from 0 to 1, and `ui.sw(0/1/2)` are white, green, and orange (active low). The handle doesn't come through `python_callback`, so poll it instead. Polling at 10–20 Hz doesn't disturb the audio.
- There's no USB audio, so the 2 V RMS line-out has to go into an audio input. The CalDigit TS3's audio-in works and shows as "CalDigit Thunderbolt 3 Audio".
- The USB drive is `FX MIC DISK`. Its FAT table got corrupted while the Mac and the firmware both had it mounted, so eject it before poking the device.

## Prior art

- https://learn.adafruit.com/hacking-the-teenage-engineering-ep-2350-ting covers the pinout, teardown, and CircuitPython.
- https://github.com/JR-One-Yard/ep-2350-usb-mic is CircuitPython USB-mic firmware and was the reference for the audio chain.
- https://github.com/au42/open-ting covers reverse-engineering of the stock firmware.
- https://github.com/bnjreece/awesome-te#ep-2350-ting-fx lists more tools and projects.
