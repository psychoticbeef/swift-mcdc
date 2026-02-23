/// Reduced Ordered Binary Decision Diagram (ROBDD).
///
/// Implements Bryant's ITE-based BDD construction with reduction:
/// - If `low == high`, the node is eliminated (returns the child directly).
/// - If a node `(variable, low, high)` already exists, it is reused (sharing).
///
/// Terminal nodes are represented as node IDs 0 (False) and 1 (True).
public struct BDD {
    /// Node ID type. 0 = False terminal, 1 = True terminal, >= 2 = internal.
    public typealias NodeRef = Int

    public static let falseTerminal: NodeRef = 0
    public static let trueTerminal: NodeRef = 1

    /// An internal BDD node: tests `variable` (by index), branches to `low` (false) and `high` (true).
    public struct Node {
        public let variable: Int
        public let low: NodeRef
        public let high: NodeRef
    }

    /// All internal nodes, keyed by node ID.
    public private(set) var nodes: [NodeRef: Node] = [:]

    /// Unique table: (variable, low, high) -> existing node ID.
    private var uniqueTable: [UniqueKey: NodeRef] = [:]

    /// Computed table for ITE memoization.
    private var computedTable: [ITEKey: NodeRef] = [:]

    /// Next available node ID (starts at 2, since 0 and 1 are terminals).
    private var nextID: NodeRef = 2

    /// Variable names for display.
    public var variableNames: [String] = []

    /// The root node of the BDD (set after construction).
    public var root: NodeRef = 0

    public init() {}

    // MARK: - Node creation with reduction

    /// Make-or-reuse a BDD node. Applies the two reduction rules:
    /// 1. If low == high, return that child (elimination).
    /// 2. If the node already exists, return the existing ID (sharing).
    public mutating func makeNode(variable: Int, low: NodeRef, high: NodeRef) -> NodeRef {
        // Reduction rule 1: elimination
        if low == high { return low }

        // Reduction rule 2: sharing
        let key = UniqueKey(variable: variable, low: low, high: high)
        if let existing = uniqueTable[key] {
            return existing
        }

        let id = nextID
        nextID += 1
        nodes[id] = Node(variable: variable, low: low, high: high)
        uniqueTable[key] = id
        return id
    }

    // MARK: - ITE (if-then-else) operation

    /// Compute `ite(f, g, h)` = if f then g else h.
    /// This is the universal BDD operation from which AND, OR, NOT derive.
    public mutating func ite(_ f: NodeRef, _ g: NodeRef, _ h: NodeRef) -> NodeRef {
        // Terminal cases
        if f == Self.trueTerminal { return g }
        if f == Self.falseTerminal { return h }
        if g == Self.trueTerminal && h == Self.falseTerminal { return f }
        if g == h { return g }

        // Check computed table
        let key = ITEKey(f: f, g: g, h: h)
        if let cached = computedTable[key] {
            return cached
        }

        // Find the top variable (lowest index among f, g, h)
        let topVar = topVariable(f, g, h)

        // Shannon expansion: restrict each operand by topVar
        let fLow = restrict(f, variable: topVar, value: false)
        let fHigh = restrict(f, variable: topVar, value: true)
        let gLow = restrict(g, variable: topVar, value: false)
        let gHigh = restrict(g, variable: topVar, value: true)
        let hLow = restrict(h, variable: topVar, value: false)
        let hHigh = restrict(h, variable: topVar, value: true)

        let low = ite(fLow, gLow, hLow)
        let high = ite(fHigh, gHigh, hHigh)

        let result = makeNode(variable: topVar, low: low, high: high)
        computedTable[key] = result
        return result
    }

    // MARK: - Boolean operations (derived from ITE)

    /// AND: f && g = ite(f, g, False)
    public mutating func and(_ f: NodeRef, _ g: NodeRef) -> NodeRef {
        ite(f, g, Self.falseTerminal)
    }

    /// OR: f || g = ite(f, True, g)
    public mutating func or(_ f: NodeRef, _ g: NodeRef) -> NodeRef {
        ite(f, Self.trueTerminal, g)
    }

    /// NOT: !f = ite(f, False, True)
    public mutating func not(_ f: NodeRef) -> NodeRef {
        ite(f, Self.falseTerminal, Self.trueTerminal)
    }

    /// Create a variable node: var(i) = ite(i, True, False)
    public mutating func variable(_ index: Int) -> NodeRef {
        makeNode(variable: index, low: Self.falseTerminal, high: Self.trueTerminal)
    }

    // MARK: - Tree check

    /// Check whether the BDD rooted at `root` is a tree.
    /// A tree means every internal (non-terminal) node has in-degree <= 1.
    /// Terminal nodes (0 and 1) are excluded — they are always shared.
    public func isTree(from root: NodeRef) -> Bool {
        var refCount: [NodeRef: Int] = [:]

        func countRefs(_ nodeRef: NodeRef) {
            // Skip terminals
            guard nodeRef != Self.falseTerminal && nodeRef != Self.trueTerminal else { return }
            guard let node = nodes[nodeRef] else { return }

            // Count references to children (non-terminal only)
            for child in [node.low, node.high] {
                if child != Self.falseTerminal && child != Self.trueTerminal {
                    refCount[child, default: 0] += 1
                    if refCount[child]! > 1 {
                        return  // Early exit: already non-tree
                    }
                }
            }

            countRefs(node.low)
            countRefs(node.high)
        }

        countRefs(root)

        return refCount.values.allSatisfy { $0 <= 1 }
    }

    /// Count the number of internal (non-terminal) nodes reachable from `root`.
    public func nodeCount(from root: NodeRef) -> Int {
        var visited = Set<NodeRef>()

        func walk(_ ref: NodeRef) {
            guard ref != Self.falseTerminal && ref != Self.trueTerminal else { return }
            guard visited.insert(ref).inserted else { return }
            if let node = nodes[ref] {
                walk(node.low)
                walk(node.high)
            }
        }

        walk(root)
        return visited.count
    }

    /// Collect all variable indices used in the BDD from `root`.
    public func variables(from root: NodeRef) -> Set<Int> {
        var vars = Set<Int>()
        var visited = Set<NodeRef>()

        func walk(_ ref: NodeRef) {
            guard ref != Self.falseTerminal && ref != Self.trueTerminal else { return }
            guard visited.insert(ref).inserted else { return }
            if let node = nodes[ref] {
                vars.insert(node.variable)
                walk(node.low)
                walk(node.high)
            }
        }

        walk(root)
        return vars
    }

    // MARK: - Helpers

    /// Find the top variable (lowest index) among the non-terminal operands.
    private func topVariable(_ f: NodeRef, _ g: NodeRef, _ h: NodeRef) -> Int {
        var result = Int.max
        if let n = nodes[f] { result = min(result, n.variable) }
        if let n = nodes[g] { result = min(result, n.variable) }
        if let n = nodes[h] { result = min(result, n.variable) }
        return result
    }

    /// Restrict a node by setting `variable` to `value`.
    private func restrict(_ ref: NodeRef, variable: Int, value: Bool) -> NodeRef {
        guard let node = nodes[ref] else { return ref }  // terminal
        if node.variable == variable {
            return value ? node.high : node.low
        }
        // Variable ordering: if node.variable < variable, this variable isn't in this subtree
        if node.variable > variable {
            return ref
        }
        return ref
    }
}

// MARK: - Hash keys

private struct UniqueKey: Hashable {
    let variable: Int
    let low: BDD.NodeRef
    let high: BDD.NodeRef
}

private struct ITEKey: Hashable {
    let f: BDD.NodeRef
    let g: BDD.NodeRef
    let h: BDD.NodeRef
}
