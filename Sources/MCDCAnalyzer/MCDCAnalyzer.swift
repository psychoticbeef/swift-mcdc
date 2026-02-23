import Foundation
import SwiftSyntax
import SwiftParser
import SwiftOperators

/// Public entry point for analyzing Swift source files for MC/DC decision structure.
///
/// Based on Comar et al. (2012): when the reduced ordered BDD of a boolean
/// expression is a tree, branch coverage implies masking MC/DC.
///
/// Mirrors the approach of GTD's MCDC Checker for C/C++:
/// 1. Find all "interesting decisions" — expressions with `&&` or `||`.
/// 2. Build a reduced ordered BDD (ROBDD) for each.
/// 3. Check if the BDD is a tree (no internal node sharing).
/// 4. If not, try variable reorderings to find a tree-like form.
public struct MCDCAnalyzerEngine: Sendable {
    /// Maximum variables for reordering attempts (n! permutations).
    public let maxReorderVariables: Int

    public init(maxReorderVariables: Int = 5) {
        self.maxReorderVariables = maxReorderVariables
    }

    /// Analyze a Swift source string and return per-function analysis results.
    public func analyze(source: String, filePath: String = "<stdin>") -> FileAnalysis {
        let parsed = Parser.parse(source: source)
        // Fold operators so that &&, ||, ternary become resolved syntax nodes
        let opTable = OperatorTable.standardOperators
        let sourceFile = (try? opTable.foldAll(parsed).as(SourceFileSyntax.self)) ?? parsed
        let converter = SourceLocationConverter(fileName: filePath, tree: sourceFile)

        // Collect functions
        let collector = FunctionCollector()
        collector.collect(from: sourceFile, converter: converter)

        let checker = BDDTreeChecker(maxReorderVariables: maxReorderVariables)

        var functionResults: [FunctionAnalysis] = []

        for fn in collector.functions {
            // Find all interesting decisions in this function
            let finder = DecisionFinder()
            finder.walk(fn.body)

            let decisions = finder.decisions.map { found in
                let result = checker.check(expr: found.expr, originalOrder: found.variableOrder)
                return DecisionAnalysis(result)
            }

            functionResults.append(FunctionAnalysis(
                name: fn.name,
                line: fn.line,
                decisions: decisions
            ))
        }

        return FileAnalysis(path: filePath, functions: functionResults)
    }

    /// Format analysis results as human-readable text.
    public static func formatText(_ analysis: FileAnalysis) -> String {
        var lines: [String] = []
        lines.append("File: \(analysis.path)")
        lines.append(String(repeating: "=", count: 60))

        if analysis.functions.isEmpty {
            lines.append("  No functions found.")
            return lines.joined(separator: "\n")
        }

        for fn in analysis.functions {
            guard !fn.decisions.isEmpty else { continue }
            lines.append("")
            lines.append("Function: \(fn.name) (line \(fn.line))")

            for (i, decision) in fn.decisions.enumerated() {
                lines.append("  Decision \(i + 1): \(decision.classification.rawValue)")
                lines.append("    Conditions: \(decision.conditionCount), BDD nodes: \(decision.nodeCount)")
                lines.append("    Variable order: \(decision.originalOrder.joined(separator: ", "))")
                if let suggested = decision.suggestedOrder {
                    lines.append("    Suggested reorder: \(suggested.joined(separator: ", "))")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Format analysis results as JSON.
    public static func formatJSON(_ analysis: FileAnalysis) throws -> String {
        let payload = JSONPayload(analysis)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Format multiple file results as JSON with a summary.
    public static func formatJSONMultiFile(_ results: [FileAnalysis]) throws -> String {
        let payload = JSONMultiFilePayload(results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - JSON encoding helpers

struct JSONPayload: Encodable {
    let path: String
    let functions: [JSONFunction]

    init(_ analysis: FileAnalysis) {
        self.path = analysis.path
        self.functions = analysis.functions.map(JSONFunction.init)
    }
}

struct JSONFunction: Encodable {
    let name: String
    let line: Int
    let decisions: [JSONDecision]

    init(_ fn: FunctionAnalysis) {
        self.name = fn.name
        self.line = fn.line
        self.decisions = fn.decisions.map(JSONDecision.init)
    }
}

struct JSONDecision: Encodable {
    let conditionCount: Int
    let nodeCount: Int
    let classification: String
    let originalOrder: [String]
    let suggestedOrder: [String]?

    init(_ d: DecisionAnalysis) {
        self.conditionCount = d.conditionCount
        self.nodeCount = d.nodeCount
        self.classification = d.classification.rawValue
        self.originalOrder = d.originalOrder
        self.suggestedOrder = d.suggestedOrder
    }
}

struct JSONMultiFilePayload: Encodable {
    let files: [JSONPayload]
    let summary: JSONSummary

    init(_ results: [FileAnalysis]) {
        self.files = results.map(JSONPayload.init)

        var totalFunctions = 0
        var functionsWithDecisions = 0
        var totalDecisions = 0
        var treeDecisions = 0
        var correctableDecisions = 0
        var nonCorrectableDecisions = 0
        var nonTreeEntries: [JSONNonTreeEntry] = []

        for file in results {
            for fn in file.functions {
                totalFunctions += 1
                totalDecisions += fn.decisions.count
                if !fn.decisions.isEmpty {
                    functionsWithDecisions += 1
                }

                treeDecisions += fn.decisions.filter { $0.classification == .treeLike }.count
                correctableDecisions += fn.decisions.filter { $0.classification == .nonTreeCorrectable }.count
                nonCorrectableDecisions += fn.decisions.filter { $0.classification == .nonTreeNonCorrectable }.count

                let problematic = fn.decisions.filter { $0.classification != .treeLike }
                if !problematic.isEmpty {
                    nonTreeEntries.append(JSONNonTreeEntry(
                        file: file.path,
                        function: fn.name,
                        line: fn.line,
                        decisions: problematic.map { JSONDecision($0) }
                    ))
                }
            }
        }

        self.summary = JSONSummary(
            filesAnalyzed: results.count,
            totalFunctions: totalFunctions,
            functionsWithDecisions: functionsWithDecisions,
            totalDecisions: totalDecisions,
            treeDecisions: treeDecisions,
            correctableDecisions: correctableDecisions,
            nonCorrectableDecisions: nonCorrectableDecisions,
            nonTreeEntries: nonTreeEntries
        )
    }
}

struct JSONSummary: Encodable {
    let filesAnalyzed: Int
    let totalFunctions: Int
    let functionsWithDecisions: Int
    let totalDecisions: Int
    let treeDecisions: Int
    let correctableDecisions: Int
    let nonCorrectableDecisions: Int
    let nonTreeEntries: [JSONNonTreeEntry]
}

struct JSONNonTreeEntry: Encodable {
    let file: String
    let function: String
    let line: Int
    let decisions: [JSONDecision]
}
