# Requirements: coiled-cable push-to-talk

The EP-2350 runs our CircuitPython firmware and connects to the Mac only by its coiled 3.5 mm cable, which goes into an audio input (the CalDigit TS3's audio-in). A small Swift menu-bar app on the Mac turns the handle into a trigger for the user's dictation tool.

Each requirement names how it's verified. **T** means an automated test that is written before the code. **M** means a manual check on hardware with a pass/fail result, listed in `docs/manual-checks.md`.

## Device (firmware)

- **D1. Voice only while talking.** The mic is audible on the line-out only while the handle is in, plus a 0.3 s release tail. *T (talk-window logic), M (listen on the line-out).*
- **D2. Pilot tracks talking.** A pilot tone plays on the line-out for exactly the talk window: it starts when the handle goes in and stops when the tail ends. *T, M.*
- **D3. The pilot stays out of transcripts.** The pilot sits above the speech band and below what the CalDigit input can capture. Its frequency and level are chosen by measurement. *M.*
- **D4. Volume.** The volume screw under the lid sets the voice level and doesn't change the pilot. *M.*
- **D5. Sleep on batteries.** After an idle period with the handle out, the device powers down. Squeezing the handle wakes it. The time from squeeze to the pilot starting after a wake must be measured and acceptable. *T (idle timer), M (measure wake latency).*
- **D6. Sleep is configurable.** The idle timeout comes from `TING_SLEEP_AFTER` (seconds) in `CIRCUITPY/settings.toml`. The default is 600, and 0 means never. *T.*
- **D7. Button tones.** Each side button has its own tone on the line-out: top 16 kHz, middle 17 kHz, bottom 19 kHz. On the FX MIC those buttons are orange, white, and gray; the Ting variant's colours differ, so code names them by position. These are provisional until M10 measures them. The tone plays while the button is held, for at least 120 ms so a quick tap is still detectable, and a release bounce can't start a second tone for 80 ms. Tones play whether or not the user is talking, and they're independent of the volume screw. A button press counts as activity for sleep (D5). Buttons can't wake a powered-off Ting; only the handle powers it on. *T (button timing, activity), M (M10: measured levels and separation).*

## Mac app

- **A1. Detection.** The app detects the pilot on the chosen input device. It reports "talking" within 150 ms of the pilot starting and "not talking" within 150 ms of it stopping. *T, using recorded fixtures.*
- **A2. No false triggers.** Speech, music, keyboard noise, and silence never register as "talking". *T, using recorded fixtures.*
- **A3. Configurable dictation tool.** The user picks what "talking" drives:
  - a **trigger**: a key chord (e.g. ⌥Space), a modifier double-tap (e.g. double ⌘), or a held key (e.g. fn).
  - a **mode**: *toggle*, where the trigger fires once on start and once on stop (Raycast), or *hold*, where the key stays down while talking.
  - Presets are provided for common tools, and the user can also define a custom trigger.

  *T for the trigger and mode state machine, M for each preset.*
- **A4. Stays in sync.** In toggle mode, a missed or bounced pilot edge can't leave the tool out of step for longer than one squeeze. Toggles are spaced at least 0.4 s apart. *T.*
- **A5. Permissions.** On first run the app requests Microphone (to listen for the pilot) and Accessibility (to send keys). It explains why, and shows clearly when a permission is missing. *M.*
- **A6. Background.** The app runs as a menu-bar app with no Dock icon and can start at login. *M.*
- **A7. Resilience.** If the input device disappears and comes back, the app recovers without a restart. If that happens mid-talk in toggle mode, it sends the stop trigger. *T (state machine), M (unplug test).*
- **A8. Pause listening.** The pilot only reaches the Mac as audio, so the app has to capture the input continuously, and macOS shows its orange mic-in-use indicator the whole time. Apps can't hide it. A menu toggle pauses listening: capture stops completely, so the indicator goes away, and the menu-bar icon shows the paused state. The setting persists across launches. Pausing mid-talk in toggle mode sends the stop trigger. *M (indicator on and off, persistence), T (stop on pause, with the trigger state machine).*
- **A9. Device settings.** A Settings window lets the user set the Ting's power-off timeout (5, 10, 20, or 30 min, or Never). The cable can only carry signal from the Ting to the Mac, so the app can only change this while the Ting is connected by USB-C: it writes `TING_SLEEP_AFTER` into `settings.toml` and keeps any other lines. When the Ting is connected, the window shows the device's current value. When it isn't, the control is disabled with an explanation. If the drive is read-only, which happens when USB reconnects while the Ting is running on battery, the window says to restart the Ting rather than failing silently. *T (settings file parsing and updating), M (connected, disconnected, and read-only states).*
- **A10. Input selection.** Settings lists every audio input, and the choice persists. With nothing chosen, the default is the first input whose name contains "CalDigit". If the chosen input isn't connected, it's listed as "(not connected)" and the app waits for it rather than falling back to another device, because silently listening on the wrong device would look like the Ting had stopped working. Changing the input ends any dictation in progress and restarts listening. Only an input the coiled cable is plugged into can hear the pilot. *T (choice logic), M (switching, unplugged choice).*

- **A11. Button mapping.** The app detects each button tone separately, even while other tones (talk, other buttons) play, and maps each button to a key. The default is top → ↑, middle → ↓, bottom → Return, which suits answering Claude Code's questions. The mapping is editable in Settings and persists. Each press sends **one** key tap (no auto-repeat for now). Keys go to whichever app is frontmost, with no per-app guard. *T (multi-tone detection, press-to-key mapping), M (M11: each button in Claude Code).*
- *Later, not now:* auto-repeat while a button is held, and per-app mappings.

## Non-goals

- Transcription. The dictation tool does that.
- USB audio or HID. A one-cable USB version was built and dropped (see `CLAUDE.md`).
- The stock TE effects and samples.
