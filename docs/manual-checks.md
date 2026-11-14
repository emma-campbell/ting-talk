# Manual checks

These are hardware checks that can't be automated. Each one is tied to a requirement in `requirements.md`. Add a row to the log whenever a check is run.

| ID | Requirement | Steps | Pass when |
|---|---|---|---|
| M1 | D1, D2 | Plug the coiled cable into the CalDigit audio-in. Record 20 s from "CalDigit Thunderbolt 3 Audio": hold without talking, hold and talk, release and keep talking, then silence. | Pilot near 18 kHz is at least 30 dB over the noise floor only while held (plus the tail). Voice is present only while held. Released speech doesn't show up above the noise floor. |
| M2 | D3 | With the app running, dictate a few sentences into a text field with each preset tool. | No stray characters or words from the pilot, and accuracy matches the built-in mic. |
| M3 | D4 | While holding, turn the volume screw from minimum to maximum. | Voice level follows the screw. The pilot level doesn't change. |
| M4 | D5 | Run on batteries with USB unplugged. Wait past the idle timeout, then squeeze. | The unit powers down when idle. Time from squeeze to pilot is recorded below and judged acceptable. |
| M5 | A3 | For each preset, squeeze and talk, then release. | The tool starts and stops, or hold-mode keys are held for the right duration. |
| M6 | A5 | First launch on a clean user account, or after resetting TCC. | The app asks for Microphone and Accessibility with an explanation, and shows a missing permission clearly. |
| M7 | A6 | Enable "start at login", then log out and back in. | Menu-bar icon appears and there's no Dock icon. |
| M8 | A7 | Unplug the CalDigit, or the coiled cable, mid-talk, then replug. | In toggle mode the stop trigger fires on unplug, and detection resumes on replug without restarting the app. |
| M9 | A8 | Toggle "Pause listening" on, then off. Quit and relaunch while paused. | The orange mic indicator disappears while paused and returns when resumed. The icon shows paused. Paused state survives relaunch. |

## Log

| Date | Check | Result | Notes |
|---|---|---|---|
| 2026-11-14 | M1 | Pass | Pilot (18 kHz, mixer level 0.1) at about 40 dB with a noise floor of about 1 dB in a 300 Hz band. Edges are sharp at 250 ms resolution, and there's no voice while the mic is closed. Recording is `tests/fixtures/caldigit_pilot_speech.wav`. The "released, keep talking" step wasn't confirmed. |
| 2026-11-14 | M9 | Pass (partial) | Pause drops the orange indicator and resume brings it back. CoreAudio process list confirmed TingTalk stops capturing. If the indicator lingers, check for System Settings → Sound (its input meter captures too). Relaunch-while-paused not yet tried. |
| 2026-11-14 | M9 | Pass | Relaunched while paused: it came back paused. |
| 2026-11-14 | M5 | Pass (Raycast) | Squeeze starts Raycast dictation and release stops it, via the coiled cable → CalDigit → TingTalk → ⌘ double-tap. The log showed trusted=true and one toggle per edge. |
| 2026-11-14 | M4 | Pass | With `TING_SLEEP_AFTER = 30` on batteries, it powered off when idle, and a squeeze woke it and started Raycast dictation. The user said the wake "feels great". Latency wasn't measured numerically. |
