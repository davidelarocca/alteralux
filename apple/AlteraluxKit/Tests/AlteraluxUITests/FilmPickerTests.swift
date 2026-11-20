import AppKit
import SwiftUI
import Testing
@testable import AlteraluxUI

extension WindowedTests {
    /// The film list works without a pointer: typing narrows it, the arrow keys move through
    /// it and Return chooses.
    @MainActor
    struct FilmPickerKeyboard {
        private func startedModel() async -> AppModel {
            let model = AppModel(dataDirectory: WindowedTests.engineData)
            await model.start()
            return model
        }

        /// The list with the keyboard in its search field, as it opens in the app. A test
        /// process is not the active app, so the field does not take the focus by itself there:
        /// the test gives it.
        private func hostedPicker(_ model: AppModel) throws -> KeyboardCheck {
            let keys = KeyboardCheck.host(width: FilmPicker.size.width, height: FilmPicker.size.height) {
                FilmPicker().environment(model)
            }
            let field = try #require(keys.window.contentView.flatMap(Self.textField))
            #expect(keys.window.makeFirstResponder(field))
            return keys
        }

        private static func textField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable {
                return field
            }
            return view.subviews.lazy.compactMap(textField).first
        }

        @Test func arrowsAndReturnChooseTheNextFilm() async throws {
            let model = await startedModel()
            #expect(model.settings.filmID == "kodak_portra_400")
            let keys = try hostedPicker(model)
            defer { keys.close() }
            keys.press(.downArrow)
            keys.press(.return)
            #expect(model.settings.filmID == "kodak_portra_800")
        }

        @Test func typingNarrowsTheListAndReturnChoosesTheMatch() async throws {
            let model = await startedModel()
            let keys = try hostedPicker(model)
            defer { keys.close() }
            for letter in ["v", "e", "l"] {
                keys.press(.character(letter))
            }
            keys.press(.return)
            #expect(model.settings.filmID == "fujifilm_velvia_100")
            // A slide is scanned directly: choosing it went through the model's rule.
            #expect(model.settings.scanFilm)
        }
    }
}
