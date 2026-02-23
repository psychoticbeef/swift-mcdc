import ArgumentParser
import Foundation
import MCDCAnalyzer

@main
struct MCDCTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcdc-tool",
        abstract: "Check if branch coverage implies MC/DC for Swift source files.",
        discussion: """
        Finds all boolean expressions with && or || operators, builds a reduced \
        ordered BDD (ROBDD) for each, and checks if the BDD is a tree. When it \
        is, branch coverage of the compiled code is sufficient for masking MC/DC \
        (Comar et al. 2012).

        When a BDD is not tree-like, the tool tries variable reorderings (up to \
        --max-reorder-vars variables) and suggests a corrected order if one exists.
        """
    )

    @Argument(help: "Swift source file(s) or directories to analyze. Directories are scanned recursively for .swift files.")
    var paths: [String]

    @Flag(name: .long, help: "Output results as JSON.")
    var json = false

    @Flag(name: .long, help: "Show only the summary with counts and non-tree decisions.")
    var summary = false

    @Option(name: .long, help: "Max variables for reordering attempts (default: 5, i.e. 5! = 120 permutations).")
    var maxReorderVars: Int = 5

    func run() throws {
        let engine = MCDCAnalyzerEngine(maxReorderVariables: maxReorderVars)
        let fm = FileManager.default

        var swiftFiles: [String] = []
        for path in paths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
                throw ValidationError("Path does not exist: \(path)")
            }
            if isDir.boolValue {
                if let enumerator = fm.enumerator(atPath: path) {
                    while let file = enumerator.nextObject() as? String {
                        if file.hasSuffix(".swift") {
                            let full = (path as NSString).appendingPathComponent(file)
                            swiftFiles.append(full)
                        }
                    }
                }
            } else {
                swiftFiles.append(path)
            }
        }

        swiftFiles.sort()

        if swiftFiles.isEmpty {
            print("No .swift files found.")
            return
        }

        var allResults: [FileAnalysis] = []
        for filePath in swiftFiles {
            let source = try String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)
            let analysis = engine.analyze(source: source, filePath: filePath)
            allResults.append(analysis)
        }

        if json {
            try printJSON(allResults)
        } else if summary {
            printSummary(allResults)
        } else {
            for analysis in allResults {
                print(MCDCAnalyzerEngine.formatText(analysis))
                print()
            }
            if allResults.count > 1 {
                printSummary(allResults)
            }
        }
    }

    func printSummary(_ results: [FileAnalysis]) {
        var totalFunctions = 0
        var functionsWithDecisions = 0
        var totalDecisions = 0
        var treeDecisions = 0
        var correctableDecisions = 0
        var nonCorrectableDecisions = 0

        struct NonTreeEntry {
            let file: String
            let function: String
            let line: Int
            let decisions: [DecisionAnalysis]
        }
        var nonTreeEntries: [NonTreeEntry] = []

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

                if !fn.isTreeLike {
                    let problematic = fn.decisions.filter { $0.classification != .treeLike }
                    nonTreeEntries.append(NonTreeEntry(
                        file: file.path,
                        function: fn.name,
                        line: fn.line,
                        decisions: problematic
                    ))
                }
            }
        }

        let nonTreeDecisions = correctableDecisions + nonCorrectableDecisions

        print(String(repeating: "=", count: 60))
        print("SUMMARY")
        print(String(repeating: "=", count: 60))
        print("Files analyzed:        \(results.count)")
        print("Total functions:       \(totalFunctions)")
        print("  with &&/|| decisions: \(functionsWithDecisions)")
        print()
        print("Decisions (&&/||):     \(totalDecisions)")
        print("  Tree-like BDDs:      \(treeDecisions)")
        print("  Non-tree BDDs:       \(nonTreeDecisions)")
        if correctableDecisions > 0 {
            print("    correctable:       \(correctableDecisions)")
        }
        if nonCorrectableDecisions > 0 {
            print("    non-correctable:   \(nonCorrectableDecisions)")
        }

        if nonTreeDecisions == 0 && totalDecisions > 0 {
            print()
            print("All \(totalDecisions) BDDs are trees.")
            print("Branch coverage is sufficient for masking MC/DC.")
        } else if totalDecisions == 0 {
            print()
            print("No compound boolean decisions found.")
        }

        if !nonTreeEntries.isEmpty {
            print()
            print(String(repeating: "-", count: 60))
            print("NON-TREE DECISIONS:")
            print(String(repeating: "-", count: 60))
            for entry in nonTreeEntries {
                print()
                print("  \(entry.file):\(entry.line) — \(entry.function)()")
                for d in entry.decisions {
                    print("    \(d.classification.rawValue): \(d.originalOrder.joined(separator: ", "))")
                    if let suggested = d.suggestedOrder {
                        print("      Suggested reorder: \(suggested.joined(separator: ", "))")
                    }
                }
            }
        }
    }

    func printJSON(_ results: [FileAnalysis]) throws {
        if results.count == 1 {
            let output = try MCDCAnalyzerEngine.formatJSON(results[0])
            print(output)
        } else {
            let output = try MCDCAnalyzerEngine.formatJSONMultiFile(results)
            print(output)
        }
    }
}
