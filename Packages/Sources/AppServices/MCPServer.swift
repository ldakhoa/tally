import Foundation
import MCPKit
import Network
import Observation

/// The local MCP server: an HTTP listener on the loopback interface only, so nothing off this
/// Mac can connect. It lives in the app (rather than a separate tool opening the database) so
/// every request sees the live store and every change is synced like one made in the app.
@MainActor
@Observable
public final class MCPServer {
    public enum State: Equatable, Sendable {
        case stopped
        case starting
        case running(port: Int)
        case failed(String)
    }

    public private(set) var state: State = .stopped

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var running: (port: Int, token: String)?
    @ObservationIgnored private let connections = MCPConnectionRegistry()
    /// Keeps macOS from napping or auto-terminating the app while clients may connect.
    @ObservationIgnored private var activity: NSObjectProtocol?

    public init() {}

    public static func url(port: Int) -> String {
        "http://127.0.0.1:\(port)\(MCPHTTPEndpoint.defaultPath)"
    }

    /// Starts, restarts or stops the server to match the settings.
    public func apply(settings: AppSettings, store: BudgetStore) {
        guard settings.mcpServerEnabled else {
            stop()
            return
        }
        guard let token = KeychainStore.mcpTokenCreatingIfNeeded() else {
            stop()
            state = .failed("Could not store the access token in the Keychain.")
            return
        }
        if let running, running.port == settings.mcpPort, running.token == token, listener != nil {
            return
        }
        start(port: settings.mcpPort, token: token, host: TallyMCPTools.host(settings: settings, store: store))
    }

    /// Starts listening on `127.0.0.1:port` (`0` picks a free port).
    public func start(port: Int, token: String, host: MCPToolHost) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            state = .failed("Invalid port \(port).")
            return
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            state = .failed(Self.describe(error, port: port))
            return
        }

        let endpoint = MCPHTTPEndpoint(token: token, core: MCPServerCore(host: host))
        let connections = self.connections
        listener.newConnectionHandler = { connection in
            MCPConnection(connection: connection, endpoint: endpoint, registry: connections).start()
        }
        listener.stateUpdateHandler = { [weak self, weak listener] newState in
            MainActor.assumeIsolated {
                guard let self, let listener, self.listener === listener else { return }
                switch newState {
                case .ready:
                    self.state = .running(port: listener.port.map { Int($0.rawValue) } ?? port)
                case .failed(let error):
                    self.stop()
                    self.state = .failed(Self.describe(error, port: port))
                case .waiting(let error):
                    self.state = .failed(Self.describe(error, port: port))
                default:
                    break
                }
            }
        }

        self.listener = listener
        self.running = (port, token)
        state = .starting
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Tally MCP server is accepting connections"
        )
        listener.start(queue: .main)
    }

    public func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        running = nil
        connections.cancelAll()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        state = .stopped
    }

    private static func describe(_ error: Error, port: Int) -> String {
        if let error = error as? NWError, case .posix(let code) = error, code == .EADDRINUSE {
            return "Port \(port) is already in use. Choose another port."
        }
        return error.localizedDescription
    }
}

/// Open client connections, so stopping the server closes them.
final class MCPConnectionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    func add(_ connection: NWConnection) {
        lock.lock()
        connections[ObjectIdentifier(connection)] = connection
        lock.unlock()
    }

    func remove(_ connection: NWConnection) {
        lock.lock()
        connections[ObjectIdentifier(connection)] = nil
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        let all = Array(connections.values)
        connections.removeAll()
        lock.unlock()
        all.forEach { $0.cancel() }
    }
}

/// One client connection: reads requests one at a time (keep-alive), answers each in order.
/// All state is touched on `queue` only.
private final class MCPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let endpoint: MCPHTTPEndpoint
    private let registry: MCPConnectionRegistry
    private let queue = DispatchQueue(label: "com.ldakhoa.tally.mcp.connection")
    private var buffer = Data()

    init(connection: NWConnection, endpoint: MCPHTTPEndpoint, registry: MCPConnectionRegistry) {
        self.connection = connection
        self.endpoint = endpoint
        self.registry = registry
    }

    func start() {
        registry.add(connection)
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .failed, .cancelled:
                registry.remove(connection)
                connection.stateUpdateHandler = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        process()
    }

    /// Answers the next whole request in the buffer, or reads more bytes.
    private func process() {
        switch HTTPRequestParser.parse(buffer) {
        case .incomplete:
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
                if let data { buffer.append(data) }
                if error != nil || (isComplete && (data?.isEmpty ?? true)) {
                    connection.cancel()
                } else {
                    process()
                }
            }
        case .failure(let response):
            send(response, close: true)
        case .request(let request, let consumed):
            buffer = Data(buffer.dropFirst(consumed))
            Task { [self] in
                let response = await endpoint.respond(to: request)
                queue.async { self.send(response, close: request.wantsClose) }
            }
        }
    }

    private func send(_ response: HTTPResponse, close: Bool) {
        connection.send(content: response.serialized(keepAlive: !close), completion: .contentProcessed { [self] error in
            if close || error != nil {
                connection.cancel()
            } else {
                process()
            }
        })
    }
}
