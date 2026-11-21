import SwiftUI
import Testing
@testable import AlteraluxUI

/// What a test reads back from the hosted view.
@MainActor
private final class Steps {
    var taken: [Int] = []
}

extension WindowedTests {
    /// While developing, the left and right arrows go through the photos: a menu never gets an
    /// arrow pressed alone, so the photo takes them itself.
    @MainActor
    struct StepThroughPhotosKeysTests {
        private func hosted(canStep: Bool = true) -> (KeyboardCheck, Steps) {
            let steps = Steps()
            let keys = KeyboardCheck.host {
                Color.clear
                    .modifier(StepThroughPhotosKeys { offset in
                        guard canStep else { return false }
                        steps.taken.append(offset)
                        return true
                    })
            }
            return (keys, steps)
        }

        @Test func theArrowsGoToThePreviousAndTheNextPhoto() {
            let (keys, steps) = hosted()
            defer { keys.close() }
            keys.press(.rightArrow)
            keys.press(.rightArrow)
            keys.press(.leftArrow)
            #expect(steps.taken == [1, 1, -1])
        }

        @Test func anArrowWithAModifierIsLeftAlone() {
            let (keys, steps) = hosted()
            defer { keys.close() }
            keys.press(.rightArrow, modifiers: .command)
            #expect(steps.taken.isEmpty)
        }
    }
}
