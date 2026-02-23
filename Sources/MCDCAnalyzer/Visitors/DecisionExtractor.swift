import SwiftSyntax

/// Information about a decision found in source code.
public struct FoundDecision {
    /// The boolean expression tree.
    public let expr: BoolExpr
    /// Variable names in left-to-right order.
    public let variableOrder: [String]
}

/// Walks a function body and finds all "interesting decisions" — expressions
/// that contain `&&` or `||` operators. Mirrors GTD's approach: only boolean
/// compound expressions are analyzed, not bare `if` or `switch` constructs.
public final class DecisionFinder: SyntaxVisitor {
    public var decisions: [FoundDecision] = []
    private let builder = BDDBuilder()

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    // Visit all expressions, looking for top-level && or ||.
    // After operator folding, nested && and || are children of the outer InfixOperatorExprSyntax.
    // Returning .skipChildren prevents visiting nested boolean subexpressions, so we always
    // see the outermost boolean expression first and extract the complete decision.
    override public func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        let op = node.operator.trimmedDescription
        guard op == "&&" || op == "||" else {
            return .visitChildren
        }

        let boolExpr = builder.extractBoolExpr(ExprSyntax(node))
        let order = builder.collectVariableOrder(boolExpr)
        decisions.append(FoundDecision(expr: boolExpr, variableOrder: order))

        return .skipChildren
    }
}
