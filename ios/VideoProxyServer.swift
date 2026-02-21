import Foundation
import Network

/// A delegate protocol for managing the lifecycle of child connections.
protocol ProxyConnectionDelegate: AnyObject {
    
    /// Notifies the delegate that a connection handler has completed its work and can be released.
    ///
    /// - Parameter id: The unique identifier of the connection handler.
    func connectionDidClose(id: String)
}

/// A TCP-based video proxy server built using Apple’s Network framework.
///
/// `VideoProxyServer` is responsible for:
/// - Creating and managing a TCP listener
/// - Accepting incoming client connections
/// - Managing the lifecycle of active connection handlers
/// - Coordinating access to shared state in a thread-safe manner
///
/// The server is designed to be idempotent, thread-safe, and resilient to listener failures.
internal final class VideoProxyServer: ProxyConnectionDelegate {
    
    /// The underlying TCP listener.
    private var listener: NWListener?
    
    /// Disk-backed storage used for caching video data.
    private let storage: VideoCacheStorage
    
    /// The local port on which the server listens for incoming connections.
    internal let port: Int
    
    /// A thread-safe registry of active client connection handlers.
    private var activeHandlers: [String: ClientConnectionHandler] = [:]
    
    /// Internal cached running state used to prevent data races.
    private var _isRunning: Bool = false
    
    /// A mutual exclusion lock used to protect all shared mutable state.
    private let serverLock = NSLock()

    /// If true, only the first few segments of each video are cached.
    private let headOnlyCache: Bool

    // Internal constant: How many segments to cache when headOnlyCache is true.
    private let HEAD_SEGMENT_LIMIT = 3
    
    /// Indicates whether the server is currently running.
    ///
    /// This property is thread-safe and reflects the authoritative server state.
    var isRunning: Bool {
        serverLock.lock()
        defer { serverLock.unlock() }
        return _isRunning
    }
    
    /// Creates a new video proxy server.
    ///
    /// - Parameters:
    ///   - port: The local TCP port to bind the listener to.
    ///   - maxCacheSize: The maximum allowed size of the disk cache, in bytes.
    ///   - headOnlyCache: If true, only the first few segments of each video are cached.
    init(port: Int, maxCacheSize: Int, headOnlyCache: Bool = false) {
        self.port = port
        self.storage = VideoCacheStorage(maxCacheSize: maxCacheSize)
        self.headOnlyCache = headOnlyCache
    }
    
    /// Starts the TCP server and begins accepting incoming connections.
    ///
    /// This method is thread-safe and prevents duplicate startup attempts.
    ///
    /// - Throws: An error if the provided port is invalid or the listener fails to initialize.
    func start() throws {
        serverLock.lock()
        defer { serverLock.unlock() }
        
        guard !_isRunning, listener == nil else {
            return
        }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.serviceClass = .responsiveData
        
        guard let localPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NSError(
                domain: "VideoProxyServer",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Invalid port: \(port)"]
            )
        }
        
        let listener = try NWListener(using: parameters, on: localPort)
        
        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .failed = state {
                DispatchQueue.global().async {
                    self.stop()
                }
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
        self._isRunning = true
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.storage.prune()
        }
    }
    
    /// Stops the server and terminates all active client connections.
    ///
    /// This method is fully idempotent and safe to call multiple times.
    func stop() {
        serverLock.lock()
        
        guard _isRunning || listener != nil else {
            serverLock.unlock()
            return
        }
        
        _isRunning = false
        listener?.cancel()
        listener = nil
        
        let handlersToStop = activeHandlers.values
        activeHandlers.removeAll()
        
        serverLock.unlock()
        
        handlersToStop.forEach { $0.stop() }
    }
    
    /// Handles a newly accepted network connection.
    ///
    /// - Parameter connection: The incoming TCP connection.
    private func handleNewConnection(_ connection: NWConnection) {
        let limit = headOnlyCache ? HEAD_SEGMENT_LIMIT : 0

        let handler = ClientConnectionHandler(
            connection: connection,
            storage: storage,
            port: port,
            initialSegmentsToCache: limit
        )
        
        handler.delegate = self
        
        var shouldStart = false
        
        serverLock.lock()
        if _isRunning {
            activeHandlers[handler.id] = handler
            shouldStart = true
        }
        serverLock.unlock()
        
        if shouldStart {
            handler.start()
        } else {
            connection.cancel()
        }
    }
    
    /// Removes a completed connection handler from the active registry.
    ///
    /// - Parameter id: The unique identifier of the closed connection.
    func connectionDidClose(id: String) {
        serverLock.lock()
        defer { serverLock.unlock() }
        activeHandlers.removeValue(forKey: id)
    }
    
    /// Clears all cached video data from persistent storage.
    func clearCache() {
        storage.clearAll()
    }
}