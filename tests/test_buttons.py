from buttons import ButtonTone
from talk import TalkWindow


def test_silent_until_pressed():
    b = ButtonTone()
    assert not b.update(False, 0.0)


def test_tone_follows_a_long_press():  # D7
    b = ButtonTone(min_on=0.12)
    assert b.update(True, 0.0)
    assert b.update(True, 0.5)
    assert not b.update(False, 0.6)


def test_a_quick_tap_still_lasts_the_minimum():  # D7: detectable taps
    b = ButtonTone(min_on=0.12)
    assert b.update(True, 0.0)
    assert b.update(False, 0.02)
    assert b.update(False, 0.11)
    assert not b.update(False, 0.13)


def test_release_bounce_cannot_start_a_second_tone():  # D7
    b = ButtonTone(min_on=0.12, gap=0.08)
    b.update(True, 0.0)
    assert not b.update(False, 0.5)
    assert not b.update(True, 0.52)  # bounce
    assert not b.update(False, 0.53)
    assert b.update(True, 0.6)  # a real second press, after the gap


def test_held_through_the_minimum_keeps_playing():
    b = ButtonTone(min_on=0.12)
    b.update(True, 0.0)
    assert b.update(True, 0.2)


def test_button_activity_postpones_sleep():  # D7 + D5
    w = TalkWindow(tail=0.3, sleep_after=60)
    w.touch(50.0)
    assert not w.should_power_off(100.0, on_usb=False)
    assert w.should_power_off(110.0, on_usb=False)
