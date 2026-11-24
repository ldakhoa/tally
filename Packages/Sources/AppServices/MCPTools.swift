import BudgetKit
import ClaudeKit
import Foundation
import MCPKit
import TallyCore

/// Tally's tools as offered to MCP clients, run against the live store.
///
/// The tools are the deterministic ones Ask Tally uses (`ExternalToolCatalog`). Changes go
/// through `AssistantService.execute`, so they are validated, saved and synced exactly like a
/// change made in the app. Salary follows the app's eye button: while it is hidden, MCP clients
/// get the same "locked" figures Ask Tally gets, and have no way to ask for it to be revealed.
@MainActor
public enum TallyMCPTools {
    public static func serverInfo(settings: AppSettings) -> MCPServerInfo {
        MCPServerInfo(
            name: "tally",
            title: "Tally",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            instructions: ExternalToolCatalog.instructions(currency: settings.currency, allowsChanges: settings.mcpAllowsChanges)
        )
    }

    public static func tools(allowsChanges: Bool) -> [MCPTool] {
        let read = ExternalToolCatalog.readTools.map {
            MCPTool(name: $0.name, description: $0.description, inputSchema: $0.inputSchema, readOnly: true)
        }
        guard allowsChanges else { return read }
        return read + ExternalToolCatalog.writeTools.map {
            MCPTool(
                name: $0.name,
                description: $0.description,
                inputSchema: $0.inputSchema,
                readOnly: false,
                destructive: ExternalToolCatalog.isDestructive($0.name)
            )
        }
    }

    /// Runs one tool; `nil` when no tool has that name.
    public static func call(
        name: String,
        arguments: JSONValue,
        settings: AppSettings,
        store: BudgetStore,
        now: Date = Date()
    ) -> MCPToolResult? {
        let toolUse = ClaudeToolUse(id: UUID().uuidString, name: name, input: arguments)

        if ExternalToolCatalog.readNames.contains(name) {
            let context = AdviserToolContext(
                data: AssistantService.adviserData(settings: settings, store: store, now: now),
                currentMemberID: settings.currentMember.id,
                members: store.knownMembers(settings: settings),
                // No consent card can be shown to an MCP client.
                salaryRequestAvailable: false
            )
            let output = ExternalToolCatalog.run(toolUse, context: context) ?? AdviserToolCatalog.run(toolUse, context: context)
            return MCPToolResult(text: output.text, isError: output.isError)
        }

        if ExternalToolCatalog.writeNames.contains(name) {
            guard settings.mcpAllowsChanges else {
                return MCPToolResult(
                    text: "Error: changes are turned off. The user can allow them in Tally > Settings > MCP Server > Allow changes.",
                    isError: true
                )
            }
            let outcome = AssistantService.execute(toolUse: toolUse, settings: settings, store: store)
            return MCPToolResult(text: outcome.toolOutput, isError: outcome.isError)
        }

        return nil
    }

    /// The host handed to the server: every request reads the current settings and store.
    public static func host(settings: AppSettings, store: BudgetStore) -> MCPToolHost {
        MCPToolHost(
            info: { await MainActor.run { serverInfo(settings: settings) } },
            tools: { await MainActor.run { tools(allowsChanges: settings.mcpAllowsChanges) } },
            call: { name, arguments in
                await MainActor.run { call(name: name, arguments: arguments, settings: settings, store: store) }
            }
        )
    }
}

/// Copy-and-paste setup for MCP clients. Checked against `claude mcp add --help` and Codex's
/// `mcp_servers` configuration keys.
public enum MCPClientSetup {
    public static let serverName = "tally"

    /// A shell command that registers the server with Claude Code for every project.
    public static func claudeCode(url: String, token: String) -> String {
        "claude mcp add --transport http --scope user \(serverName) \(url) --header \"Authorization: Bearer \(token)\""
    }

    /// A block for `~/.codex/config.toml`.
    public static func codex(url: String, token: String) -> String {
        """
        [mcp_servers.\(serverName)]
        url = "\(url)"
        http_headers = { Authorization = "Bearer \(token)" }
        """
    }

    /// The `mcpServers` JSON most other clients accept.
    public static func genericJSON(url: String, token: String) -> String {
        """
        {
          "mcpServers": {
            "\(serverName)": {
              "type": "http",
              "url": "\(url)",
              "headers": { "Authorization": "Bearer \(token)" }
            }
          }
        }
        """
    }

    /// The token as shown on screen: only its last four characters.
    public static func masked(_ token: String) -> String {
        "••••••••" + token.suffix(4)
    }
}
