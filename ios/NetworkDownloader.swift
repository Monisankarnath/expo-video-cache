import Foundation

/// Delegate protocol for receiving data transfer events from the NetworkDownloader.
protocol NetworkDownloaderDelegate: AnyObject {
    
    /// Called when the server responds with HTTP headers.
    /// - Parameters:
    ///   - task: The task that received the response.
    ///   - response: The URLResponse containing headers and status code.
    func didReceiveResponse(task: NetworkTask, response: URLResponse)
    
    /// Called when a chunk of data is received.
    /// - Parameters:
    ///   - task: The task that received data.
    ///   - data: The raw data chunk.
    func didReceiveData(task: NetworkTask, data: Data)
    
    /// Called when the download completes or fails.
    /// - Parameters:
    ///   - task: The task that completed.
    ///   - error: An optional error if the task failed.
    func didComplete(task: NetworkTask, error: Error?)
}

/// A robust download manager that handles concurrent HTTP range requests with prioritization.
///
/// This class implements a "Semaphore Pattern" to limit concurrent heavy downloads (preventing
/// socket exhaustion) while allowing lightweight metadata requests (manifests, probes) to
/// bypass the queue for instant playback startup.
final class NetworkDownloader {
    
    // MARK: - Shared Instance
    
    static let shared = NetworkDownloader()
    
    // MARK: - Properties
    
    private let sessionRouter = SessionRouter()
    
    /// Limits the number of active "heavy" downloads to prevent OS-level connection refusals.
    private let semaphore = DispatchSemaphore(value: 32)
    
    /// Serial queue for managing the download flow.
    ///
    /// This queue ensures strict FIFO execution for heavy tasks and prevents thread explosion
    /// by ensuring only one thread is blocked waiting on the semaphore at a time.
    private let queue = DispatchQueue(label: "com.videocache.downloader")
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        config.httpMaximumConnectionsPerHost = 32
        return URLSession(configuration: config, delegate: sessionRouter, delegateQueue: nil)
    }()
    
    // MARK: - API
    
    /// Initiates a download task for the specified URL and byte range.
    ///
    /// - Parameters:
    ///   - url: The remote URL to fetch.
    ///   - range: The specific byte range to download (optional).
    ///   - delegate: The responder that will handle incoming data.
    /// - Returns: A `NetworkTask` token representing the active request.
    func download(url: URL, range: Range<Int>?, delegate: NetworkDownloaderDelegate) -> NetworkTask {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        if let range = range {
            let end = (range.upperBound == Int.max) ? "" : "\(range.upperBound - 1)"
            request.addValue("bytes=\(range.lowerBound)-\(end)", forHTTPHeaderField: "Range")
        }
        
        let dataTask = session.dataTask(with: request)
        let task = NetworkTask(dataTask: dataTask, delegate: delegate, url: url.absoluteString)
        
        let urlString = url.absoluteString.lowercased()
        
        // --- Priority Detection ---
        var isPriority = url.pathExtension.lowercased() == "m3u8"
                      || urlString.contains(".m3u8")
                      || urlString.contains("init.mp4")
        
        if let r = range, (r.upperBound - r.lowerBound) < 1024 {
            isPriority = true
        }
        
        // Register the task before starting
        sessionRouter.register(task: task)
        
        if isPriority {
            // Fast Lane: Bypass semaphore
            dataTask.resume()
        } else {
            // Slow Lane: Queue safely
            queue.async {
                // 1. Setup completion handler BEFORE waiting.
                // This guarantees that if the task is cancelled or completes rapidly,
                // the signal logic is already in place.
                task.setOnComplete { [weak self] in
                    self?.semaphore.signal()
                }
                
                // 2. Wait for a slot (Blocks only this serial queue thread)
                self.semaphore.wait()
                
                // 3. Safety Check: If task was cancelled while waiting
                if task.dataTask.state == .canceling || task.dataTask.state == .completed {
                    // Manually finish to trigger the signal we just consumed via wait()
                    task.finish()
                    return
                }
                
                // 4. Start
                dataTask.resume()
            }
        }
        
        return task
    }
}

/// A wrapper around `URLSessionDataTask` that tracks delegate assignment and completion signaling.
final class NetworkTask: Hashable {
    
    let id = UUID()
    let dataTask: URLSessionDataTask
    weak var delegate: NetworkDownloaderDelegate?
    let urlString: String
    
    /// Thread-safety lock for the completion handler.
    private let lock = NSLock()
    
    /// Closure executed exactly once when the task ends.
    private var onComplete: (() -> Void)?
    
    init(dataTask: URLSessionDataTask, delegate: NetworkDownloaderDelegate, url: String) {
        self.dataTask = dataTask
        self.delegate = delegate
        self.urlString = url
    }
    
    /// Sets the completion handler in a thread-safe manner.
    func setOnComplete(_ block: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.onComplete = block
    }
    
    /// Triggers the completion handler safely.
    ///
    /// This method is idempotent: it guarantees the block is executed exactly once,
    /// preventing semaphore signal drift.
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        
        onComplete?()
        onComplete = nil
    }
    
    /// Cancels the task and triggers the completion signal immediately.
    func cancel() {
        dataTask.cancel()
        // Trigger finish immediately to release semaphore slot
        finish()
    }
    
    // MARK: - Hashable
    static func == (lhs: NetworkTask, rhs: NetworkTask) -> Bool { return lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Internal router that maps `URLSession` delegate callbacks to specific `NetworkTask` instances.
private class SessionRouter: NSObject, URLSessionDataDelegate {
    
    private var tasks = [Int: NetworkTask]()
    private let lock = NSLock()
    
    func register(task: NetworkTask) {
        lock.lock()
        tasks[task.dataTask.taskIdentifier] = task
        lock.unlock()
    }
    
    func unregister(task: URLSessionTask) {
        lock.lock()
        let networkTask = tasks.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        
        // Ensure atomic signal if it hasn't happened yet
        networkTask?.finish()
    }
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let task = tasks[dataTask.taskIdentifier]
        lock.unlock()
        
        // Safe unwrapping - prevents crash if task was removed concurrently
        if let task = task {
            task.delegate?.didReceiveResponse(task: task, response: response)
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let task = tasks[dataTask.taskIdentifier]
        lock.unlock()
        
        // Safe unwrapping
        if let task = task {
            task.delegate?.didReceiveData(task: task, data: data)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let networkTask = tasks[task.taskIdentifier]
        lock.unlock()
        
        // Safe unwrapping
        if let networkTask = networkTask {
            networkTask.delegate?.didComplete(task: networkTask, error: error)
        }
        
        // Cleanup happens here (Standard URLSession lifecycle)
        unregister(task: task)
    }
}