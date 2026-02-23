import SwiftSyntax

/// Collected information about a function declaration.
public struct CollectedFunction: Sendable {
    public let name: String
    public let line: Int
    public let body: CodeBlockSyntax

    public init(name: String, line: Int, body: CodeBlockSyntax) {
        self.name = name
        self.line = line
        self.body = body
    }
}

/// Visits a Swift syntax tree and collects all function declarations.
public final class FunctionCollector: SyntaxVisitor {
    public var functions: [CollectedFunction] = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else { return .visitChildren }
        let name = node.name.trimmedDescription
        let loc = node.startLocation(converter: locationConverter)
        functions.append(CollectedFunction(name: name, line: loc.line, body: body))
        return .visitChildren
    }

    // Also collect initializers as "init"
    override public func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else { return .visitChildren }
        let loc = node.startLocation(converter: locationConverter)
        functions.append(CollectedFunction(name: "init", line: loc.line, body: body))
        return .visitChildren
    }

    /// The location converter for mapping syntax positions to line numbers.
    var locationConverter: SourceLocationConverter!

    /// Walk the given source file syntax, using the provided converter.
    public func collect(from source: SourceFileSyntax, converter: SourceLocationConverter) {
        self.locationConverter = converter
        self.walk(source)
    }
}
