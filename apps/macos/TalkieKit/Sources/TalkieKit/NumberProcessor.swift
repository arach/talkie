import Foundation

/// Converts spoken number words to digit strings.
///
/// Follows AP Stylebook guidelines for number formatting:
/// - Spell out zero through nine (leave as words in natural mode)
/// - Use digits for 10 and above: "forty two" → "42"
/// - Always use digits for compounds: "three hundred" → "300"
/// - Always use digits for sequences: "one nine two" → "192"
///
/// Reference: Associated Press Stylebook, "numerals" entry
/// https://www.apstylebook.com — summary at https://apvschicago.com/2011/05/numbers-spell-out-or-use-numerals.html
///
/// In protocol mode (`convertSingleDigits = true`), all numbers convert
/// including single digits — "two" → "2".
public final class NumberProcessor: TokenRuleSet {

    /// When false (natural dictation), single digits 1-9 stay as words per AP style.
    /// When true (protocol mode), all numbers convert to digits.
    private let convertSingleDigits: Bool

    static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19,
    ]

    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    static let multipliers: [String: Int] = [
        "hundred": 100,
        "thousand": 1000,
    ]

    public static let allNumberWords: Set<String> = {
        var s = Set(ones.keys)
        s.formUnion(tens.keys)
        s.formUnion(multipliers.keys)
        return s
    }()

    /// - Parameter convertSingleDigits: If true, converts all numbers including 1-9.
    ///   If false, follows AP style (only converts 10+ and compounds/sequences).
    public init(convertSingleDigits: Bool = true) {
        self.convertSingleDigits = convertSingleDigits
    }

    public func consume(words: [String], at i: Int, context: inout TokenContext) -> TokenRuleResult? {
        let w = Self.normalizedWord(words[i])
        guard Self.allNumberWords.contains(w) else { return nil }
        guard let (numStr, nextI, isCompound) = consumeNumber(words: words, i: i) else { return nil }

        // AP style: spell out zero through nine when standalone
        if !convertSingleDigits && !isCompound {
            if let val = Self.ones[w], val >= 0 && val <= 9 {
                return nil // Leave as word
            }
        }

        return TokenRuleResult(numStr, nextIndex: nextI)
    }

    // MARK: - Number Consumption

    /// Returns (digitString, nextIndex, isCompound).
    /// isCompound is true if multiple tokens were consumed (sequence, compound, or multiplier).
    func consumeNumber(words: [String], i: Int) -> (String, Int, Bool)? {
        if let sequence = consumeDigitSequence(words: words, i: i) {
            return sequence
        }

        guard let phrase = consumeSpokenNumber(words: words, i: i) else {
            return nil
        }

        let consumed = phrase.nextIndex - i
        let isCompound = consumed > 1 || phrase.value >= 10
        return (String(phrase.value), phrase.nextIndex, isCompound)
    }

    private static func normalizedWord(_ word: String) -> String {
        word
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private func consumeDigitSequence(words: [String], i: Int) -> (String, Int, Bool)? {
        var digits: [Int] = []
        var j = i

        while j < words.count,
              let value = Self.ones[Self.normalizedWord(words[j])],
              value < 10 {
            digits.append(value)
            j += 1
        }

        guard digits.count >= 3 else { return nil }
        return (digits.map(String.init).joined(), j, true)
    }

    private func consumeSpokenNumber(words: [String], i: Int) -> (value: Int, nextIndex: Int)? {
        var total = 0
        var current = 0
        var j = i
        var consumedAny = false
        var canConsumeTrailingOnes = false

        while j < words.count {
            let token = Self.normalizedWord(words[j])

            if token == "and", consumedAny {
                j += 1
                continue
            }

            if let tensValue = Self.tens[token] {
                current += tensValue
                consumedAny = true
                canConsumeTrailingOnes = true
                j += 1
                continue
            }

            if let onesValue = Self.ones[token] {
                if !consumedAny {
                    current += onesValue
                    consumedAny = true
                    canConsumeTrailingOnes = false
                    j += 1
                    continue
                }

                guard canConsumeTrailingOnes else { break }
                current += onesValue
                canConsumeTrailingOnes = false
                j += 1
                continue
            }

            if let multiplier = Self.multipliers[token] {
                guard consumedAny else { break }

                current = max(current, 1) * multiplier
                if multiplier >= 1000 {
                    total += current
                    current = 0
                }

                canConsumeTrailingOnes = true
                j += 1
                continue
            }

            break
        }

        guard consumedAny else { return nil }
        return (total + current, j)
    }
}
