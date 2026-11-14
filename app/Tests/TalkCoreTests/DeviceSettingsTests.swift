import Testing
@testable import TalkCore

@Suite("A9 device settings") struct DeviceSettingsFile {
    @Test(arguments: [
        ("", 600),
        ("TING_SLEEP_AFTER = 30\n", 30),
        ("TING_SLEEP_AFTER=1200", 1200),
        ("TING_SLEEP_AFTER = 0\n", 0),
        ("# TING_SLEEP_AFTER = 5\nOTHER = 1\n", 600),  // commented out
        ("TING_SLEEP_AFTER = soon\n", 600),  // unreadable: default
        ("A = 1\nTING_SLEEP_AFTER = 1800\n", 1800),
    ])
    func readsTheSleepTimeout(toml: String, expected: Int) {
        #expect(DeviceSettings.parse(toml).sleepAfter == expected)
    }

    @Test func writesIntoAnEmptyFile() {
        #expect(DeviceSettings.updating("", sleepAfter: 600) == "TING_SLEEP_AFTER = 600\n")
    }

    @Test func replacesTheValueInPlaceKeepingOtherLines() {
        let toml = "A = 1\nTING_SLEEP_AFTER = 30\nB = \"x\"\n"
        #expect(DeviceSettings.updating(toml, sleepAfter: 0)
                == "A = 1\nTING_SLEEP_AFTER = 0\nB = \"x\"\n")
    }

    @Test func appendsWhenAbsentAndAddsTheMissingNewline() {
        #expect(DeviceSettings.updating("A = 1", sleepAfter: 600)
                == "A = 1\nTING_SLEEP_AFTER = 600\n")
    }

    @Test func leavesCommentsAlone() {
        #expect(DeviceSettings.updating("# TING_SLEEP_AFTER = 5\n", sleepAfter: 1200)
                == "# TING_SLEEP_AFTER = 5\nTING_SLEEP_AFTER = 1200\n")
    }

    @Test func collapsesDuplicateKeysIntoOne() {
        let toml = "TING_SLEEP_AFTER = 30\nA = 1\nTING_SLEEP_AFTER = 60\n"
        #expect(DeviceSettings.updating(toml, sleepAfter: 600)
                == "TING_SLEEP_AFTER = 600\nA = 1\n")
    }

    @Test func roundTrips() {
        for choice in DeviceSettings.sleepChoices {
            #expect(DeviceSettings.parse(DeviceSettings.updating("", sleepAfter: choice)).sleepAfter
                    == choice)
        }
    }

    @Test func choicesOfferNeverAndTheDefault() {
        #expect(DeviceSettings.sleepChoices.contains(0))
        #expect(DeviceSettings.sleepChoices.contains(DeviceSettings.defaultSleepAfter))
        #expect(DeviceSettings.label(forSleepAfter: 0) == "Never")
        #expect(DeviceSettings.label(forSleepAfter: 600) == "10 min")
        #expect(DeviceSettings.label(forSleepAfter: 30) == "30 s")
    }

    @Test func recognisesTheTingFromBootOut() {
        let bootOut = """
            Adafruit CircuitPython 10.3.2 on 2026-11-11; Teenage Engineering ting fx EP-2350 with rp2350a
            Board ID:teenage_engineering_ep2350
            UID:1278C4E11A89A3A8
            """
        #expect(DeviceSettings.isTing(bootOut: bootOut))
        #expect(!DeviceSettings.isTing(bootOut: "Board ID:adafruit_feather_rp2040\n"))
    }
}
