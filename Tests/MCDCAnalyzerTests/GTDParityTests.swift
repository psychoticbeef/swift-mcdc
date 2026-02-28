import Testing
@testable import MCDCAnalyzer

@Suite("GTD mcdc-checker parity tests")
struct GTDParityTests {
    // Swift translation of mcdc_checker/tests/main.c and test.h fixtures.
    let source = """
    func ifElse(_ a: Bool, _ b: Bool, _ c: Bool) -> Int {
        if (a && b) || c {
            return 5
        } else {
            return 10
        }
    }

    func ifElseTree(_ a: Bool, _ b: Bool, _ c: Bool) -> Int {
        if c || (a && b) {
            return 5
        } else {
            return 10
        }
    }

    func ifElseSimple(_ a: Bool, _ b: Bool, _ c: Bool) -> Int {
        if a && b {
            return 5
        } else if c {
            return 5
        } else {
            return 10
        }
    }

    func ifElseComparison(_ a: Int, _ b: Int, _ c: Int) -> Int {
        if a > 5 && b < 3 {
            return 5
        } else if c == 4 {
            return 5
        } else {
            return 10
        }
    }

    func testHeader(_ a: Bool, _ b: Bool, _ c: Bool) -> Bool {
        if (a && b) || c {
            return a
        } else {
            return b
        }
    }

    func returnLogical(_ a: Bool, _ b: Bool, _ c: Bool) -> Int {
        return ((a && b) || c) ? 5 : 10
    }

    func returnLogical2(_ a: Bool, _ b: Bool, _ c: Bool) -> Bool {
        return (a && b) || c
    }

    func returnBitwise(_ a: Int, _ b: Int, _ c: Int) -> Int {
        return (a & b) | c
    }

    func returnArith(_ a: Int, _ b: Int, _ c: Int) -> Int {
        return (a * b) + c
    }

    func variableAssignment(_ a: Bool, _ b: Bool, _ c: Bool) {
        let result = (a && b) || c
        _ = result
    }

    func compareVars(_ a: Int, _ b: Double, _ c: Int) -> Bool {
        return ((Double(a) < b || c > 4 || b < 2.5) && b < Double(c))
    }

    func conditionalOperator(_ a: Bool, _ b: Bool, _ c: Bool) -> Bool {
        return ((a && c) || b) ? c : false
    }

    func worstCase(_ a: Bool, _ b: Bool, _ c: Bool) -> Bool {
        return (a == (b || c) && b)
    }

    func nonCorrectable(_ a: Bool, _ b: Bool, _ c: Bool, _ d: Bool, _ e: Bool) -> Bool {
        return (a && b || c && d || e)
    }
    """

    @Test("GTD translated fixture has expected classifications")
    func translatedFixtureClassifications() {
        let engine = MCDCAnalyzerEngine(maxReorderVariables: 5)
        let result = engine.analyze(source: source, filePath: "gtd-fixture.swift")

        #expect(result.functions.count == 14)

        let byName = Dictionary(uniqueKeysWithValues: result.functions.map { ($0.name, $0) })

        let expected: [String: BDDClassification] = [
            "ifElse": .nonTreeCorrectable,
            "ifElseTree": .treeLike,
            "ifElseSimple": .treeLike,
            "ifElseComparison": .treeLike,
            "testHeader": .nonTreeCorrectable,
            "returnLogical": .nonTreeCorrectable,
            "returnLogical2": .nonTreeCorrectable,
            "variableAssignment": .nonTreeCorrectable,
            "compareVars": .nonTreeCorrectable,
            "conditionalOperator": .nonTreeCorrectable,
            // Upstream checker emits invalid_operator_nesting for this pattern.
            // Current Swift analyzer does not implement that rule and classifies the && decision itself.
            "worstCase": .treeLike,
            "nonCorrectable": .nonTreeNonCorrectable,
        ]

        for (name, classification) in expected {
            guard let fn = byName[name] else {
                Issue.record("Missing expected function: \(name)")
                continue
            }
            #expect(fn.decisions.count == 1)
            #expect(fn.decisions[0].classification == classification)
        }

        #expect(byName["returnBitwise"]?.decisions.isEmpty == true)
        #expect(byName["returnArith"]?.decisions.isEmpty == true)

        for name in ["ifElse", "testHeader", "returnLogical", "returnLogical2", "variableAssignment", "compareVars", "conditionalOperator"] {
            #expect(byName[name]?.decisions[0].suggestedOrder != nil)
        }
        #expect(byName["nonCorrectable"]?.decisions[0].suggestedOrder == nil)
    }

    @Test("GTD translated fixture summary counts")
    func translatedFixtureSummaryCounts() {
        let engine = MCDCAnalyzerEngine(maxReorderVariables: 5)
        let result = engine.analyze(source: source, filePath: "gtd-fixture.swift")

        let totalFunctions = result.functions.count
        let functionsWithDecisions = result.functions.filter { !$0.decisions.isEmpty }.count
        let decisions = result.functions.flatMap(\.decisions)

        let treeCount = decisions.filter { $0.classification == .treeLike }.count
        let correctableCount = decisions.filter { $0.classification == .nonTreeCorrectable }.count
        let nonCorrectableCount = decisions.filter { $0.classification == .nonTreeNonCorrectable }.count

        #expect(totalFunctions == 14)
        #expect(functionsWithDecisions == 12)
        #expect(decisions.count == 12)
        #expect(treeCount == 4)
        #expect(correctableCount == 7)
        #expect(nonCorrectableCount == 1)
    }
}
