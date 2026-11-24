import Foundation
import TallyCore

/// One tool offered over MCP.
public struct MCPTool: Equatable, Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue
    /// `true` when the tool only reads data.
    public var readOnly: Bool
    /// `true` when the tool deletes data.
    public var destructive: Bool

    public init(name: String, description: String, inputSchema: JSONValue, readOnly: Bool, destructive: Bool = false) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.readOnly = readOnly
        self.destructive = destructive
    }
}

public struct MCPToolResult: Equatable, Sendable {
    public var text: String
    public var isError: Bool

    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

public struct MCPServerInfo: Equatable, Sendable {
    public var name: String
    public var title: String
    public var version: String
    /// Guidance for the connecting model, sent in the `initialize` result.
    public var instructions: String

    public init(name: String, title: String, version: String, instructions: String) {
        self.name = name
        self.title = title
        self.version = version
        self.instructions = instructions
    }
}

/// What the server exposes. The closures are asked on every request, so they always reflect the
/// app's current data and settings.
public struct MCPToolHost: Sendable {
    public var info: @Sendable () async -> MCPServerInfo
    public var tools: @Sendable () async -> [MCPTool]
    /// Runs a tool; `nil` when no tool has that name.
    public var call: @Sendable (_ name: String, _ arguments: JSONValue) async -> MCPToolResult?

    public init(
        info: @escaping @Sendable () async -> MCPServerInfo,
        tools: @escaping @Sendable () async -> [MCPTool],
        call: @escaping @Sendable (_ name: String, _ arguments: JSONValue) async -> MCPToolResult?
    ) {
        self.info = info
        self.tools = tools
        self.call = call
    }
}

/// The MCP protocol itself (JSON-RPC 2.0 messages in, messages out), independent of transport.
/// Stateless: tools only, no sessions, no server-initiated messages.
public struct MCPServerCore: Sendable {
    /// Newest first. A client asking for a version not listed gets the newest.
    public static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    enum ErrorCode {
        static let parseError = -32700
        static let invalidRequest = -32600
        static let methodNotFound = -32601
        static let invalidParams = -32602
    }

    public var host: MCPToolHost

    public init(host: MCPToolHost) {
        self.host = host
    }

    /// Handles one HTTP body (a message or a batch). Returns `nil` when nothing needs answering
    /// (notifications and responses only).
    public func handle(body: Data) async -> Data? {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: body) else {
            return Self.encode(Self.error(id: .null, code: ErrorCode.parseError, message: "Parse error"))
        }
        if let batch = message.arrayValue {
            guard !batch.isEmpty else {
                return Self.encode(Self.error(id: .null, code: ErrorCode.invalidRequest, message: "Empty batch"))
            }
            var replies: [JSONValue] = []
            for item in batch {
                if let reply = await handle(message: item) { replies.append(reply) }
            }
            return replies.isEmpty ? nil : Self.encode(.array(replies))
        }
        return await handle(message: message).map(Self.encode)
    }

    func handle(message: JSONValue) async -> JSONValue? {
        guard let object = message.objectValue, object["jsonrpc"]?.stringValue == "2.0" else {
            return Self.error(id: .null, code: ErrorCode.invalidRequest, message: "Invalid request")
        }
        // A response from the client: nothing to answer.
        guard let method = object["method"]?.stringValue else {
            if object["result"] != nil || object["error"] != nil { return .none }
            return Self.error(id: object["id"] ?? .null, code: ErrorCode.invalidRequest, message: "Invalid request")
        }
        // A notification (no id): never answered.
        guard let id = object["id"], id != .null else { return .none }
        let params = object["params"] ?? .object([:])

        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.stringValue
            let version = requested.flatMap { Self.supportedVersions.contains($0) ? $0 : nil } ?? Self.supportedVersions[0]
            let info = await host.info()
            return Self.result(id: id, [
                "protocolVersion": .string(version),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": .string(info.name), "title": .string(info.title), "version": .string(info.version)],
                "instructions": .string(info.instructions),
            ])

        case "ping":
            return Self.result(id: id, [:])

        case "tools/list":
            let tools = await host.tools().map { tool -> JSONValue in
                [
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                    "annotations": [
                        "readOnlyHint": .bool(tool.readOnly),
                        "destructiveHint": .bool(tool.destructive),
                        "openWorldHint": false,
                    ],
                ]
            }
            return Self.result(id: id, ["tools": .array(tools)])

        case "tools/call":
            guard let name = params["name"]?.stringValue else {
                return Self.error(id: id, code: ErrorCode.invalidParams, message: "Missing tool name")
            }
            let arguments = params["arguments"] ?? .object([:])
            guard let outcome = await host.call(name, arguments == .null ? .object([:]) : arguments) else {
                return Self.error(id: id, code: ErrorCode.invalidParams, message: "Unknown tool: \(name)")
            }
            return Self.result(id: id, [
                "content": [["type": "text", "text": .string(outcome.text)]],
                "isError": .bool(outcome.isError),
            ])

        default:
            return Self.error(id: id, code: ErrorCode.methodNotFound, message: "Method not found: \(method)")
        }
    }

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .int(code), "message": .string(message)]]
    }

    static func encode(_ value: JSONValue) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }
}
