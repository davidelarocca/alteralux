import DesignSystem
import SwiftUI
import Testing

/// What a test reads back from a hosted slider.
@MainActor
private final class Recorder {
    var value: Double
    var isOn = true

    init(_ value: Double) {
        self.value = value
    }
}

extension WindowedTests {
    /// `ParameterSlider` promises its actions without a pointer: the arrow keys move it one
    /// step, Delete resets it to its default, and Space flips the switch of a parameter that
    /// has one. The system's "Keyboard navigation" setting does not matter: the component takes
    /// the focus by itself.
    @MainActor
    struct ParameterSliderKeyboard {
        private func hostedSlider(value: Double, defaultValue: Double = 0) -> (KeyboardCheck, Recorder) {
            let recorder = Recorder(value)
            let keys = KeyboardCheck.host {
                SliderHost("Exposure", value: value, defaultValue: defaultValue) { recorder.value = $0 }
            }
            return (keys, recorder)
        }

        @Test func rightArrowMovesOneStepUp() {
            let (keys, recorder) = hostedSlider(value: 0)
            defer { keys.close() }
            keys.press(.rightArrow)
            #expect(abs(recorder.value - 0.1) < 1e-9)
        }

        @Test func leftArrowMovesOneStepDown() {
            let (keys, recorder) = hostedSlider(value: 0)
            defer { keys.close() }
            keys.press(.leftArrow)
            #expect(abs(recorder.value + 0.1) < 1e-9)
        }

        @Test func upAndDownArrowsMoveItToo() {
            let (keys, recorder) = hostedSlider(value: 0)
            defer { keys.close() }
            keys.press(.upArrow)
            keys.press(.upArrow)
            keys.press(.downArrow)
            #expect(abs(recorder.value - 0.1) < 1e-9)
        }

        @Test func severalPressesStayOnTheSteps() {
            let (keys, recorder) = hostedSlider(value: 0)
            defer { keys.close() }
            for _ in 1 ... 7 {
                keys.press(.rightArrow)
            }
            #expect(abs(recorder.value - 0.7) < 1e-9)
        }

        @Test func arrowsStopAtTheEndOfTheRange() {
            let (keys, recorder) = hostedSlider(value: 4.9)
            defer { keys.close() }
            keys.press(.rightArrow)
            keys.press(.rightArrow)
            #expect(recorder.value == 5)
        }

        private func hostedSwitchedSlider(isOn: Bool) -> (KeyboardCheck, Recorder) {
            let recorder = Recorder(0.5)
            recorder.isOn = isOn
            let keys = KeyboardCheck.host {
                SliderHost(
                    "Grain", value: 0.5, in: 0 ... 1, isOn: isOn,
                    onChange: { recorder.value = $0 }, onSwitch: { recorder.isOn = $0 },
                )
            }
            return (keys, recorder)
        }

        @Test func spaceFlipsTheSwitch() {
            let (keys, recorder) = hostedSwitchedSlider(isOn: true)
            defer { keys.close() }
            keys.press(.space)
            #expect(!recorder.isOn)
            keys.press(.space)
            #expect(recorder.isOn)
        }

        @Test func aSwitchedOffSliderKeepsItsValue() {
            let (keys, recorder) = hostedSwitchedSlider(isOn: false)
            defer { keys.close() }
            keys.press(.rightArrow)
            keys.press(.delete)
            #expect(recorder.value == 0.5)
        }

        @Test func deleteResetsToTheDefault() {
            let (keys, recorder) = hostedSlider(value: 1.5, defaultValue: 0.5)
            defer { keys.close() }
            keys.press(.delete)
            #expect(recorder.value == 0.5)
        }
    }
}
