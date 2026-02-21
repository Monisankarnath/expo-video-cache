import Foundation
import Network

/// Manages a single active TCP connection from the media player.
///
/// This class acts as the intermediary between the client (AVPlayer) and the data source.
/// It is responsible for parsing the raw HTTP request headers, extracting the requested
/// byte range and target URL, and streaming the resulting data back to the client socket.
internal final class ClientConnectionHandler: DataSourceDelegate {

    // MARK: - Properties

    /// Unique identifier for tracing the lifecycle of this connection.
    let id = UUID().uuidString.prefix(4).description

    /// Delegate to notify the parent server when this connection closes.
    weak var delegate: ProxyConnectionDelegate?

    /// The TCP connection provided by Network framework.
    private let connection: NWConnection

    /// Shared video cache storage.
    private let storage: VideoCacheStorage

    /// The local proxy port used for manifest rewriting.
    private let port: Int

    /// The current data source responsible for fetching or streaming the requested content.
    private var dataSource: DataSource?

    /// Buffer to accumulate incoming raw HTTP request bytes.
    private var buffer = Data()

    /// Initial segments to cache.
    /// If 0, all segments are cached.
    /// If positive, only the first N segments are cached.
    private let segmentLimit: Int

    // MARK: - Initialization

    /// Initializes a new connection handler.
    ///
    /// - Parameters:
    ///   - connection: The accepted TCP connection.
    ///   - storage: The shared cache storage manager.
    ///   - port: The port number of the proxy server.
    ///   - initialSegmentsToCache: The number of initial segments to cache.
    init(connection: NWConnection, storage: VideoCacheStorage, port: Int, initialSegmentsToCache: Int) {
        self.connection = connection
        self.storage = storage
        self.port = port
        self.segmentLimit = initialSegmentsToCache
    }

    // MARK: - Lifecycle Methods

    /// Opens the socket and begins listening for incoming data.
    ///
    /// Starts a background read loop and monitors connection state.
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.stop()
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInteractive))
        readHeader()
    }

    /// Terminates the connection and releases associated resources.
    ///
    /// Cancels any active data source and closes the socket if still open.
    func stop() {
        dataSource?.cancel()
        dataSource = nil

        if connection.state != .cancelled {
            connection.cancel()
        }

        delegate?.connectionDidClose(id: id)
    }

    // MARK: - HTTP Parsing

    /// Reads incoming TCP bytes until a full HTTP header (`\r\n\r\n`) is received.
    ///
    /// Accumulates bytes in `buffer` and calls `parseRequest(_:)` once complete.
    private func readHeader() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.buffer.append(data)

                if let range = self.buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                    let headerData = self.buffer.subdata(in: 0..<range.lowerBound)
                    self.parseRequest(headerData)
                    self.buffer.removeAll(keepingCapacity: false)
                } else {
                    self.readHeader()
                }
            } else if isComplete || error != nil {
                self.stop()
            }
        }
    }

    /// Parses the raw HTTP header to extract the target URL and optional byte range.
    ///
    /// - Parameter data: Raw HTTP header bytes.
    /// - Returns: None. Initializes a `DataSource` and starts streaming.
    private func parseRequest(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return stop() }
        let lines = string.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return stop() }

        let parts = requestLine.components(separatedBy: " ")
        if parts.count < 2 { return stop() }

        let path = parts[1]
        guard let range = path.range(of: "url=") else { return stop() }

        let urlPart = String(path[range.upperBound...]).components(separatedBy: "&")[0]
        guard let decoded = urlPart.removingPercentEncoding, let url = URL(string: decoded) else { return stop() }

        var byteRange: Range<Int>? = nil
        for line in lines {
            if line.lowercased().hasPrefix("range: bytes=") {
                let val = line.dropFirst(13)
                let components = val.components(separatedBy: "-")
                if let start = Int(components[0]) {
                    let end = (components.count > 1 && !components[1].isEmpty) ? Int(components[1]) : nil
                    let safeEnd = (end != nil) ? (end! + 1) : Int.max
                    byteRange = start..<safeEnd
                }
                break
            }
        }

        dataSource = DataSource(
            storage: storage, 
            url: url, 
            range: byteRange, 
            port: port, 
            segmentLimit: segmentLimit
        )
        dataSource?.delegate = self
        dataSource?.start()
    }

    // MARK: - DataSourceDelegate Methods

    /// Called when the data source is ready to send HTTP headers.
    ///
    /// - Parameters:
    ///   - headers: HTTP headers (e.g., Content-Type, Content-Length).
    ///   - status: HTTP status code (200 or 206).
    func didReceiveHeaders(headers: [String : String], status: Int) {
        var response = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Partial Content")\r\n"
        response += "Connection: close\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"

        for (k, v) in headers {
            response += "\(k): \(v)\r\n"
        }
        response += "\r\n"

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    /// Called when a chunk of data is available from the data source.
    ///
    /// - Parameter data: Raw data to be streamed to the client.
    func didReceiveData(data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    /// Called when the data source has finished or failed.
    ///
    /// - Parameter error: Optional error if streaming failed.
    func didComplete(error: Error?) {
        if error != nil {
            stop()
        } else {
            connection.send(content: nil, contentContext: .defaultStream, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.stop()
            })
        }
    }
}
