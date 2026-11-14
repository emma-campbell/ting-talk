from talk import TalkWindow


def test_quiet_until_the_handle_goes_in():
    w = TalkWindow(tail=0.3)
    assert not w.update(False, 0.0)
    assert w.update(True, 1.0)


def test_talking_continues_through_the_release_tail():  # D1, D2
    w = TalkWindow(tail=0.3)
    w.update(True, 0.0)
    assert w.update(False, 1.0)
    assert w.update(False, 1.29)
    assert not w.update(False, 1.31)


def test_squeezing_again_inside_the_tail_keeps_talking_without_a_gap():
    w = TalkWindow(tail=0.3)
    w.update(True, 0.0)
    w.update(False, 1.0)
    assert w.update(True, 1.2)
    assert w.update(False, 2.0)
    assert not w.update(False, 2.31)


def test_not_idle_while_talking_or_before_the_timeout():  # D5
    w = TalkWindow(tail=0.3, sleep_after=60)
    assert not w.idle(0.0)
    w.update(True, 10.0)
    assert not w.idle(100.0)
    w.update(False, 100.0)
    assert not w.idle(159.0)


def test_idle_once_the_timeout_passes_after_talking_ends():  # D5
    w = TalkWindow(tail=0.3, sleep_after=60)
    w.update(True, 10.0)
    w.update(False, 20.0)
    w.update(False, 20.4)  # tail over at 20.3
    assert not w.idle(80.2)
    assert w.idle(80.4)


def test_never_powers_off_while_connected_to_usb():  # D5: batteries only
    w = TalkWindow(tail=0.3, sleep_after=60)
    assert w.idle(1000.0)
    assert not w.should_power_off(1000.0, on_usb=True)


def test_powers_off_on_battery_once_idle():  # D5
    w = TalkWindow(tail=0.3, sleep_after=60)
    assert not w.should_power_off(59.0, on_usb=False)
    assert w.should_power_off(61.0, on_usb=False)


def test_squeezing_on_battery_postpones_power_off():  # D5
    w = TalkWindow(tail=0.3, sleep_after=60)
    w.update(True, 50.0)
    w.update(False, 55.0)
    assert not w.should_power_off(100.0, on_usb=False)
    assert w.should_power_off(115.4, on_usb=False)


def test_idle_counts_from_startup_if_never_squeezed():  # D5
    w = TalkWindow(tail=0.3, sleep_after=60, started=5.0)
    assert not w.idle(64.0)
    assert w.idle(65.0)


def test_sleep_after_zero_means_never():  # D6
    w = TalkWindow(tail=0.3, sleep_after=0)
    assert not w.idle(10_000.0)
    assert not w.should_power_off(10_000.0, on_usb=False)
