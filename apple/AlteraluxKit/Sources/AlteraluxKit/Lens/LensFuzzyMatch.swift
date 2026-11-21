import Foundation

/// Word-based matching of the lens and camera names a photo carries against the names in a lens
/// database, in the way lensfun does it, so the same lens is found under the spellings cameras
/// and makers use ("FE 24-70mm F2.8 GM", "FE 24-70mm f/2.8 GM").
///
/// A name is cut into words by character class: a run of digits (with dots), a run of
/// punctuation or a run of anything else. Single punctuation marks and a lone "f" are dropped,
/// ".0" at the end of a number is dropped, and words are lowercased and sorted. A pattern
/// matches a name when every one of its words is in the name, numbers included; the score then
/// grows with the share of the name's words the pattern covers.
enum LensFuzzyMatch {
    /// The words of `text`, lowercased and in byte order, as the matching compares them.
    static func words(of text: String) -> [[UInt8]] {
        let bytes = Array(text.utf8)
        var found: [[UInt8]] = []
        var index = 0
        while index < bytes.count {
            while index < bytes.count, isSpace(bytes[index]) {
                index += 1
            }
            guard index < bytes.count else { break }

            let start = index
            index += 1
            var stripped = 0
            if isDigit(bytes[start]) {
                while index < bytes.count, isDigit(bytes[index]) || bytes[index] == dot {
                    index += 1
                }
                if index - start >= 2, bytes[index - 2] == dot, bytes[index - 1] == zero {
                    stripped = 2
                }
            } else if isPunctuation(bytes[start]) {
                while index < bytes.count, isPunctuation(bytes[index]) {
                    index += 1
                }
            } else {
                while index < bytes.count, !isSpace(bytes[index]), !isDigit(bytes[index]), !isPunctuation(bytes[index]) {
                    index += 1
                }
            }

            // A lone symbol or a lone "f" says nothing, except "+" and "*", which belong to names.
            let first = bytes[start]
            if index - start == 1, isPunctuation(first) || lowercase(first) == letterF, first != star, first != plus {
                continue
            }

            let slice = bytes[start ..< index - stripped]
            let word = (String(bytes: slice, encoding: .utf8) ?? "").lowercased()
            found.append(Array(word.utf8))
        }
        return found.sorted { compare($0, $1) < 0 }
    }

    /// How well a name with these `nameWords` matches a pattern with these `patternWords`:
    /// 0 when a pattern word is missing from the name, up to 100 for identical word lists.
    static func score(patternWords: [[UInt8]], nameWords: [[UInt8]]) -> Int {
        guard !patternWords.isEmpty, !nameWords.isEmpty else { return 0 }
        var nameIndex = 0
        var matched = 0
        for word in patternWords {
            while nameIndex < nameWords.count {
                let order = compare(word, nameWords[nameIndex])
                if order == 0 {
                    matched += 1
                    break
                }
                // Both lists are sorted: a pattern word that sorts before the next name word
                // cannot be found any more.
                if order < 0 {
                    return 0
                }
                nameIndex += 1
            }
            if nameIndex >= nameWords.count {
                return 0
            }
            nameIndex += 1
        }
        return matched * 200 / (patternWords.count + nameWords.count)
    }

    /// The best score of a pattern against any of the spellings of a name (its translations).
    static func score(patternWords: [[UInt8]], names: [String]) -> Int {
        var best = 0
        for name in names {
            best = max(best, score(patternWords: patternWords, nameWords: words(of: name)))
            if best >= 100 {
                break
            }
        }
        return best
    }

    /// Whether two names are the same apart from case.
    static func sameName(_ first: String, _ second: String) -> Bool {
        first.compare(second, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static let dot = UInt8(ascii: ".")
    private static let zero = UInt8(ascii: "0")
    private static let star = UInt8(ascii: "*")
    private static let plus = UInt8(ascii: "+")
    private static let letterF = UInt8(ascii: "f")

    private static func compare(_ first: [UInt8], _ second: [UInt8]) -> Int {
        if first == second {
            return 0
        }
        return first.lexicographicallyPrecedes(second) ? -1 : 1
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 32 || (9 ... 13).contains(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte)
    }

    /// ASCII punctuation, as the C locale sees it: bytes of non-ASCII characters are letters.
    private static func isPunctuation(_ byte: UInt8) -> Bool {
        (33 ... 47).contains(byte) || (58 ... 64).contains(byte) || (91 ... 96).contains(byte) || (123 ... 126).contains(byte)
    }

    private static func lowercase(_ byte: UInt8) -> UInt8 {
        (65 ... 90).contains(byte) ? byte + 32 : byte
    }
}
