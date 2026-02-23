/// Checks whether a BDD is tree-like, and if not, tries variable reorderings.
///
/// Mirrors GTD's approach:
/// - TREE_LIKE: BDD is a tree with the original variable order.
/// - NON_TREE_CORRECTABLE: Not a tree, but a reordering exists that makes it a tree.
/// - NON_TREE_NON_CORRECTABLE: No variable reordering produces a tree.
public struct BDDTreeChecker {
    /// Maximum number of variables for which reordering is attempted.
    /// 5! = 120 permutations, 6! = 720, 7! = 5040.
    public var maxReorderVariables: Int

    public init(maxReorderVariables: Int = 5) {
        self.maxReorderVariables = maxReorderVariables
    }

    /// Check a BDD built from a boolean expression.
    public func check(expr: BoolExpr, originalOrder: [String]) -> BDDCheckResult {
        let builder = BDDBuilder()
        let bdd = builder.buildBDD(expr: expr, variableOrder: originalOrder)

        let conditionCount = bdd.variables(from: bdd.root).count
        let nodeCount = bdd.nodeCount(from: bdd.root)

        if bdd.isTree(from: bdd.root) {
            return BDDCheckResult(
                conditionCount: conditionCount,
                nodeCount: nodeCount,
                classification: .treeLike,
                originalOrder: originalOrder,
                suggestedOrder: nil
            )
        }

        // Try reordering if within limits
        if originalOrder.count <= maxReorderVariables {
            if let reorder = findTreeLikeOrder(expr: expr, variables: originalOrder, builder: builder) {
                return BDDCheckResult(
                    conditionCount: conditionCount,
                    nodeCount: nodeCount,
                    classification: .nonTreeCorrectable,
                    originalOrder: originalOrder,
                    suggestedOrder: reorder
                )
            }
        }

        return BDDCheckResult(
            conditionCount: conditionCount,
            nodeCount: nodeCount,
            classification: .nonTreeNonCorrectable,
            originalOrder: originalOrder,
            suggestedOrder: nil
        )
    }

    /// Try all permutations of variables to find a tree-like order.
    func findTreeLikeOrder(expr: BoolExpr, variables: [String], builder: BDDBuilder) -> [String]? {
        for perm in permutations(variables) {
            let nameToIndex = Dictionary(uniqueKeysWithValues: perm.enumerated().map { ($1, $0) })
            let bdd = builder.buildBDD(expr: expr, variableOrder: perm, nameToIndex: nameToIndex)
            if bdd.isTree(from: bdd.root) {
                return perm
            }
        }
        return nil
    }
}

/// Result of checking a single decision's BDD.
public struct BDDCheckResult: Sendable {
    public let conditionCount: Int
    public let nodeCount: Int
    public let classification: BDDClassification
    public let originalOrder: [String]
    public let suggestedOrder: [String]?
}

/// Classification of a decision's BDD structure.
public enum BDDClassification: String, Sendable, Codable {
    case treeLike = "TREE"
    case nonTreeCorrectable = "NON_TREE_CORRECTABLE"
    case nonTreeNonCorrectable = "NON_TREE_NON_CORRECTABLE"
}

// MARK: - Permutation generator

func permutations<T>(_ array: [T]) -> [[T]] {
    if array.count <= 1 { return [array] }
    var result: [[T]] = []
    for i in array.indices {
        var remaining = array
        let element = remaining.remove(at: i)
        for var perm in permutations(remaining) {
            perm.insert(element, at: 0)
            result.append(perm)
        }
    }
    return result
}
