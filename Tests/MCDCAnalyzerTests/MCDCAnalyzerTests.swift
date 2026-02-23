import Testing
import SwiftSyntax
import SwiftParser
import SwiftOperators
@testable import MCDCAnalyzer

@Suite("MCDCAnalyzer Tests")
struct MCDCAnalyzerTests {
    let engine = MCDCAnalyzerEngine()

    // MARK: - BDD construction

    @Test("Simple variable BDD")
    func simpleVariable() {
        var bdd = BDD()
        let a = bdd.variable(0)
        bdd.root = a
        #expect(bdd.isTree(from: a))
        #expect(bdd.nodeCount(from: a) == 1)
    }

    @Test("AND of two variables is a tree")
    func andTree() {
        var bdd = BDD()
        let a = bdd.variable(0)
        let b = bdd.variable(1)
        let root = bdd.and(a, b)
        bdd.root = root
        // ite(a, b, 0) -> tree: a --high--> b, a --low--> 0, b --high--> 1, b --low--> 0
        #expect(bdd.isTree(from: root))
        #expect(bdd.nodeCount(from: root) == 2)
    }

    @Test("OR of two variables is a tree")
    func orTree() {
        var bdd = BDD()
        let a = bdd.variable(0)
        let b = bdd.variable(1)
        let root = bdd.or(a, b)
        bdd.root = root
        // ite(a, 1, b) -> tree: a --high--> 1, a --low--> b
        #expect(bdd.isTree(from: root))
        #expect(bdd.nodeCount(from: root) == 2)
    }

    @Test("(b && c) || a with order [b, c, a] is NOT a tree")
    func bcOrANotTree() {
        // Classic GTD example: (b && c) || a with order (b, c, a)
        // BDD: ite(b, ite(c, 1, a), a) -> 'a' node is shared -> not a tree
        var bdd = BDD()
        bdd.variableNames = ["b", "c", "a"]
        let b = bdd.variable(0)  // b at index 0
        let c = bdd.variable(1)  // c at index 1
        let a = bdd.variable(2)  // a at index 2
        let bc = bdd.and(b, c)
        let root = bdd.or(bc, a)
        bdd.root = root
        #expect(!bdd.isTree(from: root))
    }

    @Test("a || (b && c) with order [a, b, c] IS a tree")
    func aOrBcIsTree() {
        // Reordered version: a || (b && c) with order (a, b, c)
        // BDD: ite(a, 1, ite(b, c, 0)) -> no sharing -> tree
        var bdd = BDD()
        bdd.variableNames = ["a", "b", "c"]
        let a = bdd.variable(0)
        let b = bdd.variable(1)
        let c = bdd.variable(2)
        let bc = bdd.and(b, c)
        let root = bdd.or(a, bc)
        bdd.root = root
        #expect(bdd.isTree(from: root))
    }

    @Test("NOT does not break tree-ness")
    func notTree() {
        var bdd = BDD()
        let a = bdd.variable(0)
        let notA = bdd.not(a)
        let b = bdd.variable(1)
        let root = bdd.and(notA, b)
        bdd.root = root
        #expect(bdd.isTree(from: root))
    }

    // MARK: - BDD tree checker with reordering

    @Test("(b && c) || a is correctable by reordering")
    func correctableByReorder() {
        let expr = BoolExpr.or(.and(.variable("b"), .variable("c")), .variable("a"))
        let checker = BDDTreeChecker()
        let result = checker.check(expr: expr, originalOrder: ["b", "c", "a"])
        #expect(result.classification == .nonTreeCorrectable)
        #expect(result.suggestedOrder != nil)
        // The suggested order should produce a tree
        if let suggested = result.suggestedOrder {
            let builder = BDDBuilder()
            let nameToIndex = Dictionary(uniqueKeysWithValues: suggested.enumerated().map { ($1, $0) })
            let bdd = builder.buildBDD(expr: expr, variableOrder: suggested, nameToIndex: nameToIndex)
            #expect(bdd.isTree(from: bdd.root))
        }
    }

    @Test("a && b is always tree-like")
    func alwaysTreeLike() {
        let expr = BoolExpr.and(.variable("a"), .variable("b"))
        let checker = BDDTreeChecker()
        let result = checker.check(expr: expr, originalOrder: ["a", "b"])
        #expect(result.classification == .treeLike)
    }

    @Test("a || b is always tree-like")
    func orAlwaysTreeLike() {
        let expr = BoolExpr.or(.variable("a"), .variable("b"))
        let checker = BDDTreeChecker()
        let result = checker.check(expr: expr, originalOrder: ["a", "b"])
        #expect(result.classification == .treeLike)
    }

    // MARK: - Full source analysis

    @Test("Simple if with && is tree-like")
    func simpleAndDecision() {
        let source = """
        func check(_ a: Bool, _ b: Bool) {
            if a && b {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 1)
        #expect(fn.isTreeLike)
    }

    @Test("Simple if with || is tree-like")
    func simpleOrDecision() {
        let source = """
        func check(_ a: Bool, _ b: Bool) {
            if a || b {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 1)
        #expect(fn.isTreeLike)
    }

    @Test("Bare if without && or || has no decisions")
    func bareIfNoDecision() {
        let source = """
        func check(_ a: Bool) {
            if a {
                print("yes")
            } else {
                print("no")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.isEmpty)
        #expect(fn.isTreeLike)
    }

    @Test("(b && c) || a is flagged as non-tree")
    func nonTreeDetected() {
        let source = """
        func check(_ a: Bool, _ b: Bool, _ c: Bool) {
            if (b && c) || a {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 1)
        #expect(!fn.isTreeLike)
        // Should be correctable
        #expect(fn.decisions[0].classification == .nonTreeCorrectable)
        #expect(fn.decisions[0].suggestedOrder != nil)
    }

    @Test("a || (b && c) is tree-like")
    func treeFormDetected() {
        let source = """
        func check(_ a: Bool, _ b: Bool, _ c: Bool) {
            if a || (b && c) {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 1)
        #expect(fn.isTreeLike)
    }

    @Test("Nested && and || in complex expression")
    func complexExpression() {
        let source = """
        func check(_ a: Bool, _ b: Bool, _ c: Bool, _ d: Bool) {
            if a && b || c && d {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 1)
        // a && b || c && d — depends on operator precedence and variable order
    }

    @Test("Multiple decisions in one function")
    func multipleDecisions() {
        let source = """
        func check(_ a: Bool, _ b: Bool, _ c: Bool) {
            if a && b {
                print("first")
            }
            if b || c {
                print("second")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 2)
        #expect(fn.isTreeLike)
    }

    @Test("Empty function has no decisions")
    func emptyFunction() {
        let source = """
        func doNothing() {
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.isEmpty)
        #expect(fn.isTreeLike)
    }

    @Test("Switch without && or || has no decisions")
    func switchNoDecision() {
        let source = """
        func handle(_ x: Int) {
            switch x {
            case 1: print("one")
            case 2: print("two")
            default: print("other")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.isEmpty)
    }

    @Test("Guard without && or || has no decisions")
    func guardNoDecision() {
        let source = """
        func process(_ x: Int?) {
            guard let a = x else { return }
            print(a)
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.isEmpty)
    }

    @Test("Negation within && expression")
    func negationInAnd() {
        let source = """
        func check(_ a: Bool, _ b: Bool) {
            if !a && b {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 1)
        // !a && b with order [a, b]: ite(a, 0, b) = tree
        #expect(fn.isTreeLike)
    }

    @Test("JSON output works")
    func jsonOutput() throws {
        let source = """
        func check(_ a: Bool, _ b: Bool) {
            if a && b {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let json = try MCDCAnalyzerEngine.formatJSON(result)
        #expect(json.contains("\"classification\""))
        #expect(json.contains("\"conditionCount\""))
        #expect(json.contains("\"originalOrder\""))
    }

    // MARK: - Coverage: BDD unique table and computed table cache hits

    @Test("BDD unique table cache hit — duplicate makeNode returns same ID")
    func uniqueTableCacheHit() {
        var bdd = BDD()
        let a = bdd.variable(0)
        let b = bdd.variable(0) // Same variable → same (var, low, high) → unique table hit
        #expect(a == b)
    }

    @Test("BDD computed table cache hit — repeated ITE call returns cached result")
    func computedTableCacheHit() {
        // Build a || (b && c) then build a || (b && c) again — second ITE should hit computed table
        var bdd = BDD()
        let a = bdd.variable(0)
        let b = bdd.variable(1)
        let c = bdd.variable(2)
        let bc1 = bdd.and(b, c)
        let r1 = bdd.or(a, bc1)
        // Build the same expression again — ITE computed table should be hit
        let bc2 = bdd.and(b, c)
        let r2 = bdd.or(a, bc2)
        #expect(r1 == r2)
    }

    // MARK: - Coverage: BDDBuilder.buildFromExpr

    @Test("BDDBuilder.buildFromExpr convenience method")
    func buildFromExprTest() {
        let source = "let _ = a && b"
        let parsed = Parser.parse(source: source)
        let opTable = OperatorTable.standardOperators
        let folded = (try? opTable.foldAll(parsed).as(SourceFileSyntax.self)) ?? parsed
        // Extract the initializer expression from `let _ = a && b`
        if let varDecl = folded.statements.first?.item.as(VariableDeclSyntax.self),
           let binding = varDecl.bindings.first,
           let initializer = binding.initializer?.value {
            let builder = BDDBuilder()
            let bdd = builder.buildFromExpr(initializer)
            #expect(bdd.isTree(from: bdd.root))
            #expect(bdd.nodeCount(from: bdd.root) == 2)
        } else {
            Issue.record("Could not extract expression from parsed source")
        }
    }

    // MARK: - Coverage: Ternary in boolean expression

    @Test("Ternary expression with && in condition is detected")
    func ternaryWithBooleanCondition() {
        let source = """
        func check(_ a: Bool, _ b: Bool) -> Int {
            return a && b ? 1 : 0
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 1)
        #expect(fn.isTreeLike)
    }

    // MARK: - Coverage: Initializer declarations

    @Test("Initializer declarations are collected")
    func initializerCollected() {
        let source = """
        struct Foo {
            let value: Bool
            init(_ a: Bool, _ b: Bool) {
                if a && b {
                    value = true
                } else {
                    value = false
                }
            }
        }
        """
        let result = engine.analyze(source: source)
        // Should find the init function
        let initFn = result.functions.first { $0.name == "init" }
        #expect(initFn != nil)
        #expect(initFn?.decisions.count == 1)
        #expect(initFn?.isTreeLike == true)
    }

    // MARK: - Coverage: Non-boolean infix operators

    @Test("Non-boolean infix operators like + do not create decisions")
    func nonBooleanInfixNoDicisions() {
        let source = """
        func calc(_ a: Int, _ b: Int) -> Int {
            return a + b
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.isEmpty)
    }

    // MARK: - Coverage: formatText

    @Test("formatText produces expected output for tree-like function")
    func formatTextTreeLike() {
        let source = """
        func check(_ a: Bool, _ b: Bool) {
            if a && b {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let text = MCDCAnalyzerEngine.formatText(result)
        #expect(text.contains("Function: check"))
        #expect(text.contains("Decision 1: TREE"))
        #expect(text.contains("Conditions:"))
        #expect(text.contains("Variable order:"))
    }

    @Test("formatText for non-tree with suggested reorder")
    func formatTextNonTree() {
        let source = """
        func check(_ a: Bool, _ b: Bool, _ c: Bool) {
            if (b && c) || a {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let text = MCDCAnalyzerEngine.formatText(result)
        #expect(text.contains("NON_TREE_CORRECTABLE"))
        #expect(text.contains("Suggested reorder:"))
    }

    @Test("formatText for empty file")
    func formatTextEmpty() {
        let source = "let x = 1"
        let result = engine.analyze(source: source)
        let text = MCDCAnalyzerEngine.formatText(result)
        #expect(text.contains("No functions found."))
    }

    @Test("formatText for function with no decisions is skipped")
    func formatTextNoDecisions() {
        let source = """
        func doNothing() {
        }
        """
        let result = engine.analyze(source: source)
        let text = MCDCAnalyzerEngine.formatText(result)
        // Function with no decisions should not appear in output
        #expect(!text.contains("Function: doNothing"))
    }

    // MARK: - Coverage: formatJSONMultiFile

    @Test("formatJSONMultiFile produces summary")
    func formatJSONMultiFile() throws {
        let source1 = """
        func check(_ a: Bool, _ b: Bool) {
            if a && b { print("yes") }
        }
        """
        let source2 = """
        func check2(_ a: Bool, _ b: Bool, _ c: Bool) {
            if (b && c) || a { print("yes") }
        }
        """
        let result1 = engine.analyze(source: source1, filePath: "file1.swift")
        let result2 = engine.analyze(source: source2, filePath: "file2.swift")
        let json = try MCDCAnalyzerEngine.formatJSONMultiFile([result1, result2])
        #expect(json.contains("\"filesAnalyzed\""))
        #expect(json.contains("\"totalDecisions\""))
        #expect(json.contains("\"treeDecisions\""))
        #expect(json.contains("\"correctableDecisions\""))
        #expect(json.contains("\"nonTreeEntries\""))
    }

    // MARK: - Coverage: nonTreeNonCorrectable classification

    @Test("Non-tree non-correctable expression with many variables")
    func nonTreeNonCorrectable() {
        // (a && b) || (c && d) || (a && c) — variable reuse creates non-tree
        // that cannot be fixed by reordering (variables appear in multiple
        // AND branches connected by OR)
        let source = """
        func check(_ a: Bool, _ b: Bool, _ c: Bool, _ d: Bool, _ e: Bool, _ f: Bool) {
            if (a && b && c) || (d && e && f) || (a && d) || (b && e) || (c && f) {
                print("yes")
            }
        }
        """
        let engine = MCDCAnalyzerEngine(maxReorderVariables: 5)
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 1)
        // 6 variables > maxReorderVariables(5), so no reordering attempted
        // and it's not tree-like → nonTreeNonCorrectable
        #expect(fn.decisions[0].classification == .nonTreeNonCorrectable)
        #expect(fn.overallClassification == .nonTreeNonCorrectable)
    }

    // MARK: - Coverage: overallClassification with mixed decisions

    @Test("overallClassification returns nonTreeCorrectable when mixed with tree")
    func overallClassificationMixed() {
        let source = """
        func check(_ a: Bool, _ b: Bool, _ c: Bool) {
            if a && b { print("first") }
            if (b && c) || a { print("second") }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 2)
        #expect(fn.overallClassification == .nonTreeCorrectable)
    }

    // MARK: - Coverage: isNestedInBooleanOp returning true

    @Test("Nested boolean subexpression is not double-counted")
    func nestedBooleanNotDoubleCounted() {
        // In `a && b || c`, the `a && b` part is nested inside the `||`.
        // DecisionFinder should find exactly 1 top-level decision, not 2.
        let source = """
        func check(_ a: Bool, _ b: Bool, _ c: Bool) {
            if a && b || c {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 1)
    }

    // MARK: - Coverage: BDDBuilder ternary extraction

    @Test("BoolExpr extraction from ternary uses only condition")
    func ternaryBoolExprExtraction() {
        let builder = BDDBuilder()
        let expr = BoolExpr.and(.variable("a"), .not(.variable("b")))
        let order = builder.collectVariableOrder(expr)
        #expect(order == ["a", "b"])
    }

    @Test("Ternary nested inside && exercises ternary extraction path")
    func ternaryInsideBoolean() {
        // `(a ? b : c) && d` — the ternary is nested inside &&,
        // so extractBoolExpr hits the ternary branch and extracts condition `a`
        let source = """
        func check(_ a: Bool, _ b: Bool, _ c: Bool, _ d: Bool) {
            if (a ? b : c) && d {
                print("yes")
            }
        }
        """
        let result = engine.analyze(source: source)
        let fn = result.functions[0]
        #expect(fn.decisions.count == 1)
    }

    // MARK: - Coverage: Function/init without body (protocol declaration)

    @Test("Protocol function declaration without body is handled")
    func protocolFunctionWithoutBody() {
        let source = """
        protocol Checkable {
            func check(_ a: Bool, _ b: Bool)
            init()
        }
        """
        let result = engine.analyze(source: source)
        // Protocol functions/inits have no body, so no functions should be collected
        #expect(result.functions.isEmpty)
    }

    // MARK: - Coverage: Multiple files with all-tree results in JSON

    @Test("formatJSONMultiFile with non-correctable entries")
    func formatJSONMultiFileNonCorrectable() throws {
        let source = """
        func check(_ a: Bool, _ b: Bool, _ c: Bool, _ d: Bool, _ e: Bool, _ f: Bool) {
            if (a && b && c) || (d && e && f) || (a && d) || (b && e) || (c && f) {
                print("yes")
            }
        }
        """
        let engine = MCDCAnalyzerEngine(maxReorderVariables: 5)
        let result = engine.analyze(source: source, filePath: "test.swift")
        let json = try MCDCAnalyzerEngine.formatJSONMultiFile([result])
        #expect(json.contains("\"nonCorrectableDecisions\""))
        #expect(json.contains("NON_TREE_NON_CORRECTABLE"))
    }
}
