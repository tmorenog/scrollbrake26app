import Foundation

/// How hard the cognitive challenge shown before an unlock is.
public enum ChallengeDifficulty: String, Codable, CaseIterable, Comparable, Sendable {
    case none
    case easy
    case medium
    case hard

    private var rank: Int {
        switch self {
        case .none: return 0
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        }
    }

    public static func < (lhs: ChallengeDifficulty, rhs: ChallengeDifficulty) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// A locally generated arithmetic problem. Answers are always non-negative integers.
public struct MathChallenge: Codable, Equatable, Sendable {
    public let id: UUID
    public let difficulty: ChallengeDifficulty
    /// Human-readable expression, e.g. "62 − 27" or "(17 × 4) − 23".
    public let prompt: String
    public let answer: Int

    public init(id: UUID = UUID(), difficulty: ChallengeDifficulty, prompt: String, answer: Int) {
        self.id = id
        self.difficulty = difficulty
        self.prompt = prompt
        self.answer = answer
    }

    /// Accepts surrounding whitespace and a typographic minus sign.
    public func isCorrect(_ input: String) -> Bool {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{2212}", with: "-")
        guard let value = Int(normalized) else { return false }
        return value == answer
    }
}

/// Generates challenges offline. Pass a seeded generator for deterministic tests.
public enum MathChallengeGenerator {
    static let plus = "+"
    static let minus = "\u{2212}"
    static let times = "\u{00D7}"
    static let divide = "\u{00F7}"

    /// Returns `nil` for `.none`, which means "no challenge".
    public static func make<R: RandomNumberGenerator>(
        _ difficulty: ChallengeDifficulty,
        using rng: inout R
    ) -> MathChallenge? {
        switch difficulty {
        case .none:
            return nil
        case .easy:
            return easy(using: &rng)
        case .medium:
            return medium(using: &rng)
        case .hard:
            return hard(using: &rng)
        }
    }

    public static func make(_ difficulty: ChallengeDifficulty) -> MathChallenge? {
        var rng = SystemRandomNumberGenerator()
        return make(difficulty, using: &rng)
    }

    // Easy: two-digit ± one/low-two-digit, e.g. "14 + 9", "31 − 12".
    private static func easy<R: RandomNumberGenerator>(using rng: inout R) -> MathChallenge {
        if Bool.random(using: &rng) {
            let a = Int.random(in: 10...39, using: &rng)
            let b = Int.random(in: 2...15, using: &rng)
            return MathChallenge(difficulty: .easy, prompt: "\(a) \(plus) \(b)", answer: a + b)
        } else {
            let a = Int.random(in: 20...49, using: &rng)
            let b = Int.random(in: 2...19, using: &rng)
            return MathChallenge(difficulty: .easy, prompt: "\(a) \(minus) \(b)", answer: a - b)
        }
    }

    // Medium: two-digit ± two-digit, or a single-digit times table, e.g. "47 + 38", "8 × 7".
    private static func medium<R: RandomNumberGenerator>(using rng: inout R) -> MathChallenge {
        switch Int.random(in: 0..<3, using: &rng) {
        case 0:
            let a = Int.random(in: 25...79, using: &rng)
            let b = Int.random(in: 15...59, using: &rng)
            return MathChallenge(difficulty: .medium, prompt: "\(a) \(plus) \(b)", answer: a + b)
        case 1:
            let a = Int.random(in: 50...99, using: &rng)
            let b = Int.random(in: 11...(a - 5), using: &rng)
            return MathChallenge(difficulty: .medium, prompt: "\(a) \(minus) \(b)", answer: a - b)
        default:
            let a = Int.random(in: 6...9, using: &rng)
            let b = Int.random(in: 3...9, using: &rng)
            return MathChallenge(difficulty: .medium, prompt: "\(a) \(times) \(b)", answer: a * b)
        }
    }

    // Hard: two operations, e.g. "(17 × 4) − 23", "144 ÷ 12 + 19". Division is always exact.
    private static func hard<R: RandomNumberGenerator>(using rng: inout R) -> MathChallenge {
        if Bool.random(using: &rng) {
            let a = Int.random(in: 11...19, using: &rng)
            let b = Int.random(in: 3...6, using: &rng)
            let c = Int.random(in: 5...min(49, a * b - 1), using: &rng)
            return MathChallenge(
                difficulty: .hard,
                prompt: "(\(a) \(times) \(b)) \(minus) \(c)",
                answer: a * b - c
            )
        } else {
            let divisor = Int.random(in: 6...12, using: &rng)
            let quotient = Int.random(in: 6...12, using: &rng)
            let c = Int.random(in: 5...25, using: &rng)
            return MathChallenge(
                difficulty: .hard,
                prompt: "\(divisor * quotient) \(divide) \(divisor) \(plus) \(c)",
                answer: quotient + c
            )
        }
    }
}

/// Small deterministic PRNG (SplitMix64) for tests and the DEBUG harness.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
