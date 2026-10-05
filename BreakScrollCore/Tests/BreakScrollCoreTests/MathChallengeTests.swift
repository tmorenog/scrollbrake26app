import XCTest
@testable import BreakScrollCore

final class MathChallengeTests: XCTestCase {
    func testNoneProducesNoChallenge() {
        var rng = SeededGenerator(seed: 1)
        XCTAssertNil(MathChallengeGenerator.make(.none, using: &rng))
    }

    func testPromptsEvaluateToTheirAnswersWithStandardPrecedence() throws {
        var rng = SeededGenerator(seed: 42)
        for difficulty in [ChallengeDifficulty.easy, .medium, .hard] {
            for _ in 0..<2_000 {
                let challenge = try XCTUnwrap(MathChallengeGenerator.make(difficulty, using: &rng))
                XCTAssertEqual(challenge.difficulty, difficulty)
                XCTAssertGreaterThanOrEqual(challenge.answer, 0, challenge.prompt)
                XCTAssertEqual(try ExpressionEvaluator.evaluate(challenge.prompt), challenge.answer, challenge.prompt)
            }
        }
    }

    func testDifficultyShapes() throws {
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<500 {
            let easy = try XCTUnwrap(MathChallengeGenerator.make(.easy, using: &rng))
            XCTAssertLessThan(easy.answer, 60)
            XCTAssertFalse(easy.prompt.contains("\u{00D7}") || easy.prompt.contains("\u{00F7}"))

            let hard = try XCTUnwrap(MathChallengeGenerator.make(.hard, using: &rng))
            XCTAssertEqual(ExpressionEvaluator.operatorCount(hard.prompt), 2, hard.prompt)
        }
    }

    func testSameSeedGivesSameSequence() {
        var a = SeededGenerator(seed: 99)
        var b = SeededGenerator(seed: 99)
        for _ in 0..<50 {
            XCTAssertEqual(
                MathChallengeGenerator.make(.medium, using: &a)?.prompt,
                MathChallengeGenerator.make(.medium, using: &b)?.prompt
            )
        }
    }

    func testAnswerParsing() {
        let challenge = MathChallenge(difficulty: .easy, prompt: "14 + 9", answer: 23)
        XCTAssertTrue(challenge.isCorrect("23"))
        XCTAssertTrue(challenge.isCorrect("  23\n"))
        XCTAssertFalse(challenge.isCorrect("22"))
        XCTAssertFalse(challenge.isCorrect(""))
        XCTAssertFalse(challenge.isCorrect("twenty-three"))
        XCTAssertFalse(challenge.isCorrect("23.0"))

        let negative = MathChallenge(difficulty: .easy, prompt: "x", answer: -5)
        XCTAssertTrue(negative.isCorrect("\u{2212}5"))
        XCTAssertTrue(negative.isCorrect("-5"))
    }
}

/// Independent evaluator so the tests don't trust the generator's own arithmetic.
/// Integer-only; fails on inexact division.
enum ExpressionEvaluator {
    struct Failure: Error {}

    static func operatorCount(_ prompt: String) -> Int {
        prompt.filter { "+\u{2212}\u{00D7}\u{00F7}".contains($0) }.count
    }

    static func evaluate(_ prompt: String) throws -> Int {
        var tokens = tokenize(prompt)[...]
        let value = try parseSum(&tokens)
        guard tokens.isEmpty else { throw Failure() }
        return value
    }

    private static func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        var number = ""
        for ch in s where ch != " " {
            if ch.isNumber {
                number.append(ch)
            } else {
                if !number.isEmpty { out.append(number); number = "" }
                out.append(String(ch))
            }
        }
        if !number.isEmpty { out.append(number) }
        return out
    }

    private static func parseSum(_ t: inout ArraySlice<String>) throws -> Int {
        var value = try parseProduct(&t)
        while let op = t.first, op == "+" || op == "\u{2212}" {
            t.removeFirst()
            let rhs = try parseProduct(&t)
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private static func parseProduct(_ t: inout ArraySlice<String>) throws -> Int {
        var value = try parseAtom(&t)
        while let op = t.first, op == "\u{00D7}" || op == "\u{00F7}" {
            t.removeFirst()
            let rhs = try parseAtom(&t)
            if op == "\u{00D7}" {
                value *= rhs
            } else {
                guard rhs != 0, value % rhs == 0 else { throw Failure() }
                value /= rhs
            }
        }
        return value
    }

    private static func parseAtom(_ t: inout ArraySlice<String>) throws -> Int {
        guard let token = t.popFirst() else { throw Failure() }
        if token == "(" {
            let value = try parseSum(&t)
            guard t.popFirst() == ")" else { throw Failure() }
            return value
        }
        guard let value = Int(token) else { throw Failure() }
        return value
    }
}
