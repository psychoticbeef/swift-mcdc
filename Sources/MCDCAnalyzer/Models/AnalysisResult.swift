/// Analysis result for one decision (one `&&`/`||` expression) within a function.
public struct DecisionAnalysis: Sendable {
    /// Number of distinct condition variables.
    public let conditionCount: Int
    /// Number of internal BDD nodes.
    public let nodeCount: Int
    /// Classification of the BDD structure.
    public let classification: BDDClassification
    /// Variable order used for initial BDD construction.
    public let originalOrder: [String]
    /// Suggested variable reordering that makes the BDD tree-like (if correctable).
    public let suggestedOrder: [String]?

    public init(_ result: BDDCheckResult) {
        self.conditionCount = result.conditionCount
        self.nodeCount = result.nodeCount
        self.classification = result.classification
        self.originalOrder = result.originalOrder
        self.suggestedOrder = result.suggestedOrder
    }
}

/// Analysis result for an entire function.
public struct FunctionAnalysis: Sendable {
    public let name: String
    public let line: Int
    public let decisions: [DecisionAnalysis]

    public init(name: String, line: Int, decisions: [DecisionAnalysis]) {
        self.name = name
        self.line = line
        self.decisions = decisions
    }

    /// Overall classification: worst-case across all decisions.
    public var overallClassification: BDDClassification {
        if decisions.contains(where: { $0.classification == .nonTreeNonCorrectable }) {
            return .nonTreeNonCorrectable
        }
        if decisions.contains(where: { $0.classification == .nonTreeCorrectable }) {
            return .nonTreeCorrectable
        }
        return .treeLike
    }

    /// Whether all decisions are tree-like.
    public var isTreeLike: Bool {
        overallClassification == .treeLike
    }
}

/// Top-level result for one source file.
public struct FileAnalysis: Sendable {
    public let path: String
    public let functions: [FunctionAnalysis]

    public init(path: String, functions: [FunctionAnalysis]) {
        self.path = path
        self.functions = functions
    }
}
