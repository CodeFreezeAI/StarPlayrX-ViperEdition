//
//  HttpServerIO.swift
//  StarPlayrXServe
//
//  Copyright (c) 2025 Todd Bruss. All rights reserved.
//

import Foundation
import Network
import Dispatch

public protocol HttpServerIODelegate: AnyObject {
    func socketConnectionReceived(_ connection: NWConnection)
}

open class HttpServerIO {
    internal init(delegate: HttpServerIODelegate? = nil, listener: NWListener? = nil, connections: [NWConnection] = [], stateValue: Int32 = HttpServerIOState.stopped.rawValue) {
        self.delegate = delegate
        self.listener = listener
        self.connections = connections
        self.stateValue = stateValue
    }
        
    public weak var delegate: HttpServerIODelegate?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var listenerRestartTimer: DispatchSourceTimer?
    
    public enum HttpServerIOState: Int32 {
        case starting
        case running
        case stopping
        case stopped
    }
    
    private var stateValue: Int32 = HttpServerIOState.stopped.rawValue
    
    public private(set) var state: HttpServerIOState {
        get {
            HttpServerIOState(rawValue: stateValue) ?? HttpServerIOState.stopped
        }
        set(state) {
            self.stateValue = state.rawValue
        }
    }
        
    private let queue = DispatchQueue.main

    public func port() throws -> Int {
        guard let port = listener?.port?.rawValue else {
            throw SocketError.socketCreationFailed("Failed to get port")
        }
        return Int(port)
    }
    
    deinit {
        stopListenerRestartTimer()
        stop()
    }
    
    private func startListenerRestartTimer() {
        stopListenerRestartTimer()
        
        listenerRestartTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        listenerRestartTimer?.schedule(deadline: .now() + 60, repeating: 60) // Check every 60 seconds
        listenerRestartTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            if self.state != .running {
                print("Server not running, attempting to restart listener...")
                do {
                    if let port = self.listener?.port?.rawValue {
                        try self.start(port)
                    }
                } catch {
                    print("Failed to restart listener: \(error)")
                }
            }
        }
        listenerRestartTimer?.resume()
    }
    
    private func stopListenerRestartTimer() {
        listenerRestartTimer?.cancel()
        listenerRestartTimer = nil
    }
    
    public func start(_ port: in_port_t, priority: DispatchQoS.QoSClass = .userInteractive) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw SocketError.socketCreationFailed("Invalid port")
        }
        
        guard let listener = try? NWListener(using: parameters, on: port) else {
            throw SocketError.socketCreationFailed("Failed to create listener")
        }
        
        self.listener = listener
        self.state = .running
        
        listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                print("Listener ready on port \(port)")
                self.state = .running
                self.startListenerRestartTimer()
            case .failed(let error):
                print("Listener failed with error: \(error)")
                self.stop()
                
                // Try to restart after error
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self = self else { return }
                    do {
                        try self.start(port.rawValue)
                    } catch {
                        print("Failed to restart listener after error: \(error)")
                    }
                }
            case .cancelled:
                print("Listener cancelled")
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] (connection: NWConnection) in
            guard let self = self else { return }
            
            // Start the connection first
            connection.start(queue: DispatchQueue.global(qos: priority))
            
            DispatchQueue.global(qos: priority).async {
                self.queue.async {
                    self.connections.append(connection)
                }
                
                self.handleConnection(connection)
                
                self.queue.async {
                    if let index = self.connections.firstIndex(where: { $0 === connection }) {
                        self.connections.remove(at: index)
                    }
                }
            }
        }
        
        listener.start(queue: DispatchQueue.global(qos: priority))
    }
    
    public func stop() {
        autoreleasepool {
            self.state = .stopping
            stopListenerRestartTimer()

            for connection in self.connections {
                connection.cancel()
            }
            
            self.connections.removeAll()
            listener?.cancel()
            self.state = .stopped
        }
    }
    
    open func dispatch(_ request: HttpRequest) -> dispatchHttpReq {
        ([:], { _ in HttpResponse.notFound(nil) })
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let parser = HttpParser()
        
        connection.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                print("Connection ready")
            case .failed(let error):
                // Check for ECONNRESET (Connection reset by peer - error code 54)
                if let posixError = error as? POSIXError, posixError.code == .ECONNRESET {
                    print("Connection reset by peer - client disconnected")
                } else {
                    print("Connection failed: \(error)")
                }
                
                connection.cancel()
                
                // Remove from connections array
                self.queue.async {
                    if let index = self.connections.firstIndex(where: { $0 === connection }) {
                        self.connections.remove(at: index)
                    }
                }
            case .cancelled:
                print("Connection cancelled")
                
                // Remove from connections array
                self.queue.async {
                    if let index = self.connections.firstIndex(where: { $0 === connection }) {
                        self.connections.remove(at: index)
                    }
                }
            default:
                break
            }
        }
        
        func receiveData() {
            // Use a larger buffer size to accommodate JSON payloads
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] content, contentContext, isComplete, error in
                if let error = error {
                    // Check for ECONNRESET (Connection reset by peer - error code 54)
                    if let posixError = error as? POSIXError, posixError.code == .ECONNRESET {
                        print("Connection reset by peer while receiving - client disconnected")
                    } else {
                        print("Receive error: \(error)")
                    }
                    connection.cancel()
                    return
                }
                
                if let data = content, !data.isEmpty {
                    do {
                        // Parse the data - this may return nil if we need more data
                        if let request = try parser.parse(data) {
                            if let body = request.body, !body.isEmpty {
                                print("Request body: \(String(data: body, encoding: .utf8) ?? "[Non-UTF8 data]")")
                            }
                            
                            // Check if this is an .m3u8 file request (HLS streaming)
                            let isStreamRequest = request.path.hasSuffix(".m3u8") || request.path.hasSuffix(".ts")
                            
                            var mutableRequest = request
                            let (params, handler) = self?.dispatch(request) ?? ([:], { _ in HttpResponse.notFound(nil) })
                            mutableRequest.params = params
                            
                            let response = handler(mutableRequest)
                            
                            // For streaming requests, we always want to keep the connection alive
                            let keepConnection = isStreamRequest ? true : parser.supportsKeepAlive(request.headers)
                            
                            // Respond to the client
                            do {
                                _ = try self?.respond(connection, response: response, keepAlive: keepConnection, isStreamRequest: isStreamRequest)
                                
                                if !keepConnection {
                                    connection.cancel()
                                    return
                                }
                            } catch {
                                // Handle response errors
                                if let posixError = error as? POSIXError, posixError.code == .ECONNRESET {
                                    print("Connection reset by peer during response - client disconnected")
                                } else {
                                    print("Response error: \(error)")
                                }
                                connection.cancel()
                                return
                            }
                        }
                    } catch {
                        print("Parse error: \(error)")
                        connection.cancel()
                        return
                    }
                }
                
                // Continue receiving data if the connection is still active
                if !isComplete {
                    receiveData()
                } else {
                    connection.cancel()
                }
            }
        }
        
        receiveData()
    }
    
    private func respond(_ connection: NWConnection, response: HttpResponse, keepAlive: Bool, isStreamRequest: Bool = false) throws -> Bool {
        try autoreleasepool {
            var responseHeader = "HTTP/1.1 \(response.statusCode) \(response.reasonPhrase)\r\n"
            
            let content = response.content()
            responseHeader.append("Content-Length: \(content.length)\r\n")
            
            if keepAlive {
                responseHeader.append("Connection: keep-alive\r\n")
                responseHeader.append("Keep-Alive: timeout=60\r\n") // Add timeout directive
            } else {
                responseHeader.append("Connection: close\r\n")
            }
            
            // Add HLS-specific headers if this is a streaming request
            if isStreamRequest {
                // Disable caching for streaming content
                responseHeader.append("Cache-Control: no-cache, no-store, must-revalidate\r\n")
                responseHeader.append("Pragma: no-cache\r\n")
                responseHeader.append("Expires: 0\r\n")
            }
            
            for (name, value) in response.headers() {
                responseHeader.append("\(name): \(value)\r\n")
            }
            responseHeader.append("\r\n")
            
            // Use a semaphore to wait for the header send to complete
            let headerSent = DispatchSemaphore(value: 0)
            var headerError: Error?
            
            // Send headers
            connection.send(content: responseHeader.data(using: .utf8)!, completion: .contentProcessed { error in
                if let error = error {
                    if let posixError = error as? POSIXError, posixError.code == .ECONNRESET {
                        print("Connection reset by peer while sending headers - client disconnected")
                    } else {
                        print("Header write error: \(error)")
                    }
                    headerError = error
                }
                headerSent.signal()
            })
            
            // Wait for header to be sent
            headerSent.wait()
            
            // If we got an error sending the header, throw it
            if let error = headerError {
                throw error
            }
            
            // Send body if it exists
            if let writeClosure = content.write {
                // Use a semaphore to wait for the body send to complete
                let bodySent = DispatchSemaphore(value: 0)
                var bodyError: Error?
                
                let context = SignalingInnerWriteContext(
                    connection: connection,
                    completionSemaphore: bodySent,
                    onError: { error in
                        bodyError = error
                    }
                )
                
                do {
                    try writeClosure(context)
                } catch {
                    print("Body write error: \(error)")
                    connection.cancel()
                    return false
                }
                
                // Wait for body to be sent
                bodySent.wait()
                
                // If we got an error sending the body, throw it
                if let error = bodyError {
                    throw error
                }
            }
            
            // For non-keep-alive connections, we need to flush and close
            if !keepAlive {
                let flushSemaphore = DispatchSemaphore(value: 0)
                var flushError: Error?
                
                connection.send(content: Data(), completion: NWConnection.SendCompletion.contentProcessed { error in
                    if let error = error {
                        if let posixError = error as? POSIXError, posixError.code == .ECONNRESET {
                            print("Connection reset by peer during flush - client disconnected")
                        } else {
                            print("Flush error: \(error)")
                        }
                        flushError = error
                    }
                    flushSemaphore.signal()
                })
                flushSemaphore.wait()
                
                // If we got an error during flush, throw it
                if let error = flushError {
                    throw error
                }
            }
            
            // For stream requests, a slightly longer delay helps maintain the connection
            if isStreamRequest {
                Thread.sleep(forTimeInterval: 0.3)
            } else {
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            return keepAlive
        }
    }
    
    private struct SignalingInnerWriteContext: HttpResponseBodyWriter {
        let connection: NWConnection
        let completionSemaphore: DispatchSemaphore
        let onError: ((Error) -> Void)?
        
        init(connection: NWConnection, completionSemaphore: DispatchSemaphore, onError: ((Error) -> Void)? = nil) {
            self.connection = connection
            self.completionSemaphore = completionSemaphore
            self.onError = onError
        }
        
        func write(byts data: [UInt8]) throws {
            let dataSent = DispatchSemaphore(value: 0)
            
            connection.send(content: Data(data), completion: .contentProcessed { error in
                if let error = error {
                    // Check for specific error: Connection reset by peer (54)
                    if let posixError = error as? POSIXError, posixError.code == .ECONNRESET {
                        print("Connection reset by peer - client likely disconnected")
                    } else {
                        print("Write error: \(error)")
                    }
                    onError?(error)
                }
                dataSent.signal()
            })
            
            dataSent.wait()
            completionSemaphore.signal()
        }
        
        func write(data: Data) throws {
            let dataSent = DispatchSemaphore(value: 0)
            
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    // Check for specific error: Connection reset by peer (54)
                    if let posixError = error as? POSIXError, posixError.code == .ECONNRESET {
                        print("Connection reset by peer - client likely disconnected")
                    } else {
                        print("Write error: \(error)")
                    }
                    onError?(error)
                }
                dataSent.signal()
            })
            
            dataSent.wait()
            completionSemaphore.signal()
        }
    }
} 
