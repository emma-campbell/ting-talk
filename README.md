# Ting Talk

Turn a teenage engineering **EP-2350** (the FX MIC / "Ting") into a push-to-talk mic for dictation on a Mac. Squeeze the handle to start dictating and let go to stop. The three side buttons become keys, so you can answer an agent's multiple-choice questions without touching the keyboard.

Everything runs over the mic's own **coiled cable**. There's no USB cable on your desk once it's set up.

> **Status: early and in testing.** It works end to end on one setup (mine), and setup is manual. Expect rough edges, and if you hit one, I'd like to hear about it. Tooling to make setup easy is the next big piece of work.

## How it works

The Ting runs custom CircuitPython firmware instead of TE's. The firmware does two things with the audio that comes out of the coiled cable:

- **Your voice, only while you squeeze** the handle, plus a 0.3 s tail so your last word isn't cut off.
- **Quiet, high-pitched tones that carry the controls.** An 18 kHz tone plays for as long as you're talking, and each side button has its own tone while you hold it. They sit above the range of speech, so they shouldn't end up in your transcripts. It's the same trick FM radio uses: a 19 kHz pilot tone tells receivers "this is stereo".

On the Mac, a small menu-bar app (**TingTalk**) listens to the input the cable is plugged into. When it hears the talk tone, it presses your dictation tool's shortcut. When it hears a button's tone, it presses that button's key.

| Control | Tone | Default action |
|---|---|---|
| Handle (squeeze) | 18 kHz | Start/stop dictation (double-tap ⌘, the shortcut I use for Raycast) |
| Top button (orange) | 16 kHz | ↑, repeats while held |
| Middle button (white) | 17 kHz | ↓, repeats while held |
| Bottom button (gray) | 19 kHz | Return, on a **quick click** only |

Return and Escape are deliberately cautious. Whichever button they're mapped to, they're sent when you let go, and only if you clicked quickly. **Holding the button sends nothing**, so you can't submit or cancel something by accident.

Why tones over a cable instead of USB? The USB-C port sits under the lower lid, which makes it awkward to leave plugged in. The coiled cable is the cable the Ting was designed around. An earlier version used USB, with the Ting acting as a USB mic and keyboard, and it worked well. `CLAUDE.md` has the story and the lessons from it.

## What you need

- **An EP-2350.** I've only tested the **FX MIC** variant. The Ting variant should be the same board, but its buttons are different colours.
- **An audio input that accepts a line-level signal**, for the coiled cable. I use the audio-in jack on a **CalDigit TS3** dock. A USB audio adapter with a line or mic input should also work, but I haven't tried one. The Mac's own headphone jack **won't work**: it's a headphone/headset jack, not a line input, so it can't record the Ting. It won't damage anything; it just won't hear it.
- **An Apple silicon Mac** (M1 or later) running macOS 14 or newer. There's no Intel build. Xcode is only needed if you build the app yourself.
- **A USB-C cable that carries data**, for setup only. A charge-only cable shows nothing at all, which is confusing.
- **2 × AAA batteries** for day-to-day use.
- **A dictation tool with a toggle shortcut.** Today that has to be **double-tap ⌘**: I set my Raycast dictation hotkey to that. Choosing your own shortcut is planned but not built yet (see "Known gaps" below).

## Setup (manual, for now)

### 1. Flash CircuitPython onto the Ting

This replaces TE's firmware. It's reversible (see "Going back to stock"), but it **erases the stock effects and samples**.

1. Download **CircuitPython 10.3.2** for the [teenage engineering EP-2350](https://circuitpython.org/board/teenage_engineering_ep2350/).
2. Remove the lower lid and connect USB-C to your Mac.
3. **Hold the handle in, and double-click the small button above the USB-C port.** A drive called `FX MIC BOOT` (or `TING BOOT`) appears.
4. Keep holding the handle and drag the `.uf2` onto that drive. When a drive called `CIRCUITPY` appears, you can let go.

### 2. Install the firmware

With `CIRCUITPY` mounted:

```sh
firmware/install.sh
```

Then restart the Ting so it picks up `boot.py`: press the small button above the USB-C port, and squeeze the handle if it stays dark.

### 3. Build and open the Mac app

```sh
scripts/build-app.sh
open dist/TingTalk.app
```

A microphone icon appears in the menu bar. There's no Dock icon. The first time, a **setup window** walks you through two permissions, one at a time:

- **Microphone**, so the app can listen for the tones.
- **Accessibility**, so it can press keys for you. The step ticks off by itself once you switch TingTalk on in System Settings.

Then it asks you to squeeze the handle and press a button to check everything's heard. You can reopen it any time from the menu (**Setup…**).

### 4. Plug in the coiled cable and configure

1. Plug the Ting's coiled cable into your audio input.
2. Open **Settings…** from the menu-bar icon (or press ⌘,):
   - **Audio input:** the input the cable is plugged into. It defaults to anything named "CalDigit".
   - **Buttons:** a key for each button, whether it repeats while held, and the repeat delay and rate.
   - **Ting → Power off after:** how long the Ting waits before switching itself off on battery (default 10 minutes). Changing this needs the Ting connected over USB-C, because the coiled cable only carries sound one way.
3. In your **dictation tool**, choose the **same input** as its microphone, so it hears the Ting.

Squeeze, talk, let go. The menu-bar icon fills in while you're talking.

## Using it

- **Squeeze to talk.** The first squeeze after the Ting has powered itself off also turns it back on. It takes a moment to boot, so give it a beat before you start talking. The side buttons can't wake it; only the handle can.
- **Pause listening** (in the menu) when you don't need it. macOS shows its orange "mic in use" indicator whenever any app is listening to an input, and TingTalk has to listen all the time to hear the tones. Pausing stops listening completely, so the indicator goes away.
- **On USB power**, the Ting stays on and never sleeps.

## Known gaps and weirdness

Things I know about. If you find something that isn't on this list, that's useful.

- **The dictation shortcut is fixed to double-tap ⌘ (toggle).** Choosing a different shortcut, or a hold-to-talk tool, isn't built yet.
- **The tool can get out of step.** In toggle mode the app can't see whether your dictation tool is actually on. If you stop dictation some other way (Esc, or the tool timing out), the next squeeze stops it instead of starting it. One more squeeze puts it back in step.
- **It isn't notarized**, and it can't start at login yet. Downloaded builds need right-click → Open the first time, and may ask for Accessibility again after an update.
- **Whether the tones stay out of transcripts** hasn't been checked carefully. I haven't noticed any problems, but I haven't tested for them deliberately either.
- **Plugging USB back in while the Ting is running on battery** can leave the `CIRCUITPY` drive read-only. Restart the Ting (the small button above the USB-C port, then squeeze if it stays dark) and it's writable again.
- **The tones are fairly quiet.** Detection is reliable on my setup, but other audio inputs might need them louder.

## Going back to stock

Download the stock firmware from [teenage engineering](https://teenage.engineering/downloads/ep-2350). Flash it the same way as CircuitPython (hold the handle, double-click the small button, drag the `.uf2` on). Use the file for **your** variant: the zip contains both an `fx_mic` and a `ting` build.

## Development

```sh
uv run pytest                   # firmware logic (firmware/lib), runs on your Mac
cd app && swift test            # app logic: tone detection, triggers, button mapping, settings
scripts/build-app.sh 0.1.0 1    # build dist/TingTalk.app (Apple silicon, ad-hoc signed)
scripts/check-app.sh            # verify the built bundle
```

If you're rebuilding often, sign with your own Apple Development certificate (`SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh`). With ad-hoc signing, macOS treats every build as a new app and asks for Accessibility again.

CI runs both test suites on every pull request and attaches a built `TingTalk.app` to the run. Releases are cut by hand: run the **Release** workflow from the Actions tab and give it a version. It tests and builds `main`, then publishes a GitHub Release with the app attached. The app isn't notarized yet, so the first time you open a downloaded copy, right-click it and choose **Open**.

- `firmware/`: CircuitPython for the Ting. Logic that can be tested lives in `firmware/lib` as plain Python, so the same file runs on the device and under pytest.
- `app/`: the Swift package. `TalkCore` is pure and tested; `TingTalk` is the menu-bar app.
- `docs/requirements.md`: what it should do. Work here is test-first against these requirements.
- `docs/manual-checks.md`: the hardware checks that can't be automated, and a log of when each last passed.
- `CLAUDE.md`: architecture notes and the gotchas that cost me an afternoon each.

## Thanks

This leans heavily on other people's digging:

- Adafruit's [Hacking the Teenage Engineering EP-2350 Ting](https://learn.adafruit.com/hacking-the-teenage-engineering-ep-2350-ting) guide (pinout, teardown, CircuitPython), and their MIT-licensed `adafruit_nau88l21`, `adafruit_bus_device`, and `adafruit_register` libraries, vendored in `firmware/lib`.
- [ep-2350-usb-mic](https://github.com/JR-One-Yard/ep-2350-usb-mic), the reference for the audio chain.
- [open-ting](https://github.com/au42/open-ting), reverse-engineering of the stock firmware.
- [awesome-te](https://github.com/bnjreece/awesome-te#ep-2350-ting-fx), where I found all of the above.

## License

MIT. See [LICENSE](LICENSE). The vendored Adafruit libraries in `firmware/lib` keep their own MIT notices.

If you build on this, a link back here would be lovely. It's not required, just appreciated.
