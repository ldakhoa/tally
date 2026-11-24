// swift-tools-version: 5.9
import PackageDescription

/// Domain modules: pure Foundation, no SwiftUI, SwiftData, or UIKit.
/// Each depends only on modules above it in the list, preventing cycles.
let domainModules: [(name: String, dependencies: [String])] = [
    ("TallyCore", []),
    ("ThemeTokens", ["TallyCore"]),
    ("ClaudeKit", ["TallyCore"]),
    ("MCPKit", ["TallyCore"]),
    ("BudgetKit", ["TallyCore", "ClaudeKit"]),
    ("SyncKit", ["TallyCore", "BudgetKit"]),
]

/// UI foundations, SwiftData persistence, and shared services.
let platformModules: [(name: String, dependencies: [String])] = [
    ("DesignSystem", ["TallyCore", "ThemeTokens", "BudgetKit"]),
    ("Persistence", ["TallyCore", "BudgetKit"]),
    ("AppServices", [
        "TallyCore", "ThemeTokens", "ClaudeKit", "MCPKit", "BudgetKit", "SyncKit", "DesignSystem", "Persistence",
    ]),
]

/// Tiered feature UI modules: never import upward or sideways.
let featureModules: [(name: String, dependencies: [String])] = [
    // Tier 0: shared feature building blocks reading AppServices.
    ("SharedUI", ["TallyCore", "BudgetKit", "DesignSystem", "AppServices"]),
    // Tier 1: top-level screens, independent of each other.
    ("OverviewUI", ["TallyCore", "BudgetKit", "DesignSystem", "AppServices", "SharedUI"]),
    ("TransactionsUI", ["TallyCore", "BudgetKit", "DesignSystem", "AppServices", "SharedUI"]),
    ("StatisticsUI", ["TallyCore", "BudgetKit", "DesignSystem", "AppServices", "SharedUI"]),
    ("BudgetsUI", ["TallyCore", "BudgetKit", "DesignSystem", "AppServices", "SharedUI"]),
    ("GoalsUI", ["TallyCore", "BudgetKit", "DesignSystem", "AppServices", "SharedUI"]),
    ("AssistantUI", ["TallyCore", "ClaudeKit", "BudgetKit", "DesignSystem", "AppServices", "SharedUI"]),
    // Tier 2 (top): Settings sheet and panes.
    ("SettingsUI", [
        "TallyCore", "ThemeTokens", "ClaudeKit", "BudgetKit", "SyncKit", "DesignSystem", "AppServices", "SharedUI",
    ]),
]

let allModules = domainModules + platformModules + featureModules

let tests: [String: [String]] = [
    "TallyCore": [],
    "ThemeTokens": ["TallyCore"],
    "ClaudeKit": ["TallyCore"],
    "MCPKit": ["TallyCore"],
    "BudgetKit": ["TallyCore", "ClaudeKit"],
    "SyncKit": ["TallyCore", "BudgetKit"],
    // Store/sync wiring tests run against an in-memory SwiftData container (never the app's store).
    "AppServices": ["TallyCore", "ClaudeKit", "MCPKit", "BudgetKit", "SyncKit", "Persistence"],
]

func makeTargets(_ name: String, dependencies: [String]) -> [Target] {
    let resources: [Resource]? = name == "DesignSystem" ? [.process("Resources")] : nil
    var result: [Target] = [
        .target(name: name, dependencies: dependencies.map { .target(name: $0) }, resources: resources)
    ]
    if let extra = tests[name] {
        result.append(.testTarget(
            name: "\(name)Tests",
            dependencies: ([name] + extra).map { .target(name: $0) }
        ))
    }
    return result
}

let package = Package(
    name: "Tally",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TallyKit", targets: allModules.map(\.name)),
    ],
    targets: allModules.flatMap { makeTargets($0.name, dependencies: $0.dependencies) }
)
