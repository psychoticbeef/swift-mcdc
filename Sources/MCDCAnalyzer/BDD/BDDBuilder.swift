import SwiftSyntax

/// A boolean expression tree node, independent of syntax.
public indirect enum BoolExpr {
    case variable(String)
    case and(BoolExpr, BoolExpr)
    case or(BoolExpr, BoolExpr)
    case not(BoolExpr)
}

/// Builds BDDs from Swift boolean expressions.
///
/// Extracts a `BoolExpr` tree from SwiftSyntax, determines variable order,
/// then constructs an ROBDD.
public struct BDDBuilder {

    public init() {}

    /// Extract a boolean expression tree from a SwiftSyntax expression.
    public func extractBoolExpr(_ expr: ExprSyntax) -> BoolExpr {
        // Strip parentheses
        if let tuple = expr.as(TupleExprSyntax.self),
           tuple.elements.count == 1,
           let inner = tuple.elements.first?.expression {
            return extractBoolExpr(inner)
        }

        // Handle infix && and ||
        if let infix = expr.as(InfixOperatorExprSyntax.self) {
            let op = infix.operator.trimmedDescription
            if op == "&&" {
                let lhs = extractBoolExpr(infix.leftOperand)
                let rhs = extractBoolExpr(infix.rightOperand)
                return .and(lhs, rhs)
            } else if op == "||" {
                let lhs = extractBoolExpr(infix.leftOperand)
                let rhs = extractBoolExpr(infix.rightOperand)
                return .or(lhs, rhs)
            }
        }

        // Handle prefix ! (negation)
        if let prefix = expr.as(PrefixOperatorExprSyntax.self),
           prefix.operator.trimmedDescription == "!" {
            return .not(extractBoolExpr(prefix.expression))
        }

        // Handle ternary: only the condition part (same as GTD)
        if let ternary = expr.as(TernaryExprSyntax.self) {
            return extractBoolExpr(ternary.condition)
        }

        // Leaf: atomic condition variable
        return .variable(expr.trimmedDescription)
    }

    /// Collect variable names in left-to-right order from a BoolExpr.
    public func collectVariableOrder(_ expr: BoolExpr) -> [String] {
        var seen = Set<String>()
        var order: [String] = []

        func walk(_ e: BoolExpr) {
            switch e {
            case .variable(let name):
                if seen.insert(name).inserted {
                    order.append(name)
                }
            case .and(let lhs, let rhs), .or(let lhs, let rhs):
                walk(lhs)
                walk(rhs)
            case .not(let inner):
                walk(inner)
            }
        }

        walk(expr)
        return order
    }

    /// Build a BDD from a BoolExpr with the given variable order.
    public func buildBDD(expr: BoolExpr, variableOrder: [String]) -> BDD {
        var bdd = BDD()
        bdd.variableNames = variableOrder

        let nameToIndex = Dictionary(uniqueKeysWithValues: variableOrder.enumerated().map { ($1, $0) })
        bdd.root = buildNode(expr: expr, bdd: &bdd, nameToIndex: nameToIndex)
        return bdd
    }

    /// Build a BDD from a SwiftSyntax expression.
    public func buildFromExpr(_ expr: ExprSyntax) -> BDD {
        let boolExpr = extractBoolExpr(expr)
        let order = collectVariableOrder(boolExpr)
        return buildBDD(expr: boolExpr, variableOrder: order)
    }

    /// Build a BDD from a BoolExpr with a specific variable order (for reordering).
    public func buildBDD(expr: BoolExpr, variableOrder: [String], nameToIndex: [String: Int]) -> BDD {
        var bdd = BDD()
        bdd.variableNames = variableOrder
        bdd.root = buildNode(expr: expr, bdd: &bdd, nameToIndex: nameToIndex)
        return bdd
    }

    // MARK: - Recursive BDD construction

    private func buildNode(expr: BoolExpr, bdd: inout BDD, nameToIndex: [String: Int]) -> BDD.NodeRef {
        switch expr {
        case .variable(let name):
            guard let index = nameToIndex[name] else {
                // Unknown variable, treat as a new one
                return BDD.trueTerminal
            }
            return bdd.variable(index)

        case .and(let lhs, let rhs):
            let l = buildNode(expr: lhs, bdd: &bdd, nameToIndex: nameToIndex)
            let r = buildNode(expr: rhs, bdd: &bdd, nameToIndex: nameToIndex)
            return bdd.and(l, r)

        case .or(let lhs, let rhs):
            let l = buildNode(expr: lhs, bdd: &bdd, nameToIndex: nameToIndex)
            let r = buildNode(expr: rhs, bdd: &bdd, nameToIndex: nameToIndex)
            return bdd.or(l, r)

        case .not(let inner):
            let i = buildNode(expr: inner, bdd: &bdd, nameToIndex: nameToIndex)
            return bdd.not(i)
        }
    }
}
