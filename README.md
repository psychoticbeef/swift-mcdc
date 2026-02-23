# mcdc-tool

*_Warning_: This is unvalidated and vibe coded. Do not use for any serious project.*

A static analysis tool that checks whether **branch coverage implies MC/DC** for Swift source files.

It finds all compound boolean expressions (`&&`, `||`), builds a [reduced ordered BDD](https://en.wikipedia.org/wiki/Binary_decision_diagram) for each, and checks if the BDD is a tree. When all BDDs are trees, branch coverage of the compiled code is sufficient for [masking MC/DC](https://en.wikipedia.org/wiki/Modified_condition/decision_coverage) — no additional MC/DC-specific test cases are needed.

Based on the formal proof by [Comar et al. (2012)](https://hal.science/hal-02263438v1) and follows the same approach as [GTD's MCDC Checker](https://gitlab.com/gtd-gmbh/mcdc-checker/mcdc-checker) for C/C++.

## Quick start

```bash
swift build
swift run mcdc-tool path/to/Sources/
```

## Example

Given this Swift file:

```swift
func treeForm(_ a: Bool, _ b: Bool, _ c: Bool) {
    if a || (b && c) { print("yes") }
}

func nonTreeForm(_ a: Bool, _ b: Bool, _ c: Bool) {
    if (b && c) || a { print("yes") }
}
```

```
$ mcdc-tool example.swift

Function: treeForm (line 1)
  Decision 1: TREE
    Conditions: 3, BDD nodes: 3
    Variable order: a, b, c

Function: nonTreeForm (line 5)
  Decision 1: NON_TREE_CORRECTABLE
    Conditions: 3, BDD nodes: 3
    Variable order: b, c, a
    Suggested reorder: b, a, c
```

`treeForm` is fine — branch coverage gives you MC/DC for free. `nonTreeForm` has a non-tree BDD because the variable order `b, c, a` causes node sharing. The tool suggests reordering to `b, a, c` (i.e., rewriting as `b && (a || c)` or equivalent) to make it tree-like.

## Scanning a codebase

```bash
# Summary only
mcdc-tool --summary path/to/project/

# Full details
mcdc-tool path/to/project/

# JSON output for CI
mcdc-tool --json path/to/project/
```

Example summary:

```
============================================================
SUMMARY
============================================================
Files analyzed:        353
Total functions:       2576
  with &&/|| decisions: 84

Decisions (&&/||):     172
  Tree-like BDDs:      169
  Non-tree BDDs:       3
    correctable:       1
    non-correctable:   2

------------------------------------------------------------
NON-TREE DECISIONS:
------------------------------------------------------------

  Sources/Foo.swift:42 — validate()
    NON_TREE_CORRECTABLE: b, c, a
      Suggested reorder: a, b, c

  Sources/Bar.swift:87 — process()
    NON_TREE_NON_CORRECTABLE: a, b, c, d, e, f
```

## How it works

### The theorem

> When the reduced ordered BDD of a boolean expression is a tree, object branch coverage implies masking MC/DC.
>
> — Comar, Guitton, Hainque, Quinot. *Formalization and Comparison of MCDC and Object Branch Coverage Criteria.* ERTS 2012.

### What this means in practice

Under short-circuit evaluation, the compiler generates branch sequences that correspond to a BDD. If that BDD is a tree (no internal node is shared between branches), then covering every branch edge automatically produces test pairs that demonstrate each condition's independent effect on the decision outcome — which is exactly MC/DC.

### What the tool does

1. **Parse** Swift source with [swift-syntax](https://github.com/swiftlang/swift-syntax), folding operators to resolve `&&`, `||`, and ternary expressions.
2. **Find** all "interesting decisions" — expressions containing `&&` or `||`. Simple `if a { }` without compound operators is not a decision (branch coverage trivially covers it).
3. **Build** a reduced ordered BDD for each decision using Bryant's ITE algorithm. The BDD represents the mathematical boolean function, not the control flow. Reduction rules (node elimination and sharing) canonicalize the representation.
4. **Check** if the BDD is a tree: every internal node must have in-degree <= 1. Terminal nodes (true/false) are excluded from this check.
5. **Reorder** (if non-tree and <= 5 variables): try all permutations of the variable order to find one that produces a tree-like BDD.

### Classifications

| Classification | Meaning |
|---|---|
| `TREE` | BDD is a tree. Branch coverage = MC/DC. |
| `NON_TREE_CORRECTABLE` | BDD is not a tree, but a variable reordering exists that makes it one. The suggested reorder is reported. |
| `NON_TREE_NON_CORRECTABLE` | No variable reordering produces a tree. MC/DC requires dedicated test case construction. |

### The classic example

`(b && c) || a` with variable order `b, c, a`:

```
BDD: ite(b, ite(c, 1, a), a)
                          ^-- 'a' node is shared (in-degree 2) -> NOT a tree
```

Rewritten as `a || (b && c)` with order `a, b, c`:

```
BDD: ite(a, 1, ite(b, c, 0))
                              -> no sharing -> TREE
```

Both expressions are logically equivalent, but only the second form produces a tree-shaped BDD where branch coverage guarantees MC/DC.

## Options

```
USAGE: mcdc-tool <paths> ... [--json] [--summary] [--max-reorder-vars <n>]

ARGUMENTS:
  <paths>               Swift source file(s) or directories to analyze.
                        Directories are scanned recursively for .swift files.

OPTIONS:
  --json                Output results as JSON.
  --summary             Show only the summary with counts and non-tree decisions.
  --max-reorder-vars    Max variables for reordering attempts (default: 5).
```

## Building and testing

```bash
swift build
swift test
```

Requires Swift 6.0+ and pulls [swift-syntax 600.0.1](https://github.com/swiftlang/swift-syntax) and [swift-argument-parser](https://github.com/apple/swift-argument-parser) as dependencies.

## References

- Comar, Guitton, Hainque, Quinot. [*Formalization and Comparison of MCDC and Object Branch Coverage Criteria.*](https://www.adacore.com/uploads_gems/Couverture_ERTS-2012.pdf) ERTS 2012.
- Chilenski. [*An Investigation of Three Forms of the Modified Condition Decision Coverage (MCDC) Criterion.*](https://www.faa.gov/sites/faa.gov/files/aircraft/air_cert/design_approvals/air_software/AR-01-18_MCDC.pdf) FAA DOT/FAA/AR-01/18, 2001.
- Hayhurst, Veerhusen, Chilenski, Rierson. [*A Practical Tutorial on Modified Condition/Decision Coverage.*](https://shemesh.larc.nasa.gov/fm/papers/Hayhurst-2001-tm210876-MCDC.pdf) NASA/TM-2001-210876.
- GTD GmbH. [MCDC Checker for C/C++.](https://gitlab.com/gtd-gmbh/mcdc-checker/mcdc-checker)
