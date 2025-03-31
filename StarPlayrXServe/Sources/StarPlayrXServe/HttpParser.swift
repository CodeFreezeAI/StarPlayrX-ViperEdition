//
//  HttpParser.swift
//  StarPlayrXServe
//
//  Copyright (c) 2025 Todd Bruss. All rights reserved.
//

import Foundation

class HttpParser {
    private var buffer = Data()
    private let maxBufferSize = 65536
    private var isParsingHeaders = true
    private var contentLength = 0
    
    // Store the request details while waiting for the body
    private var currentMethod = ""
    private var currentPath = ""
    private var currentHeaders: [String: String] = [:]
    
    func parse(_ data: Data) throws -> HttpRequest? {
        buffer.append(data)
        
        guard buffer.count <= maxBufferSize else {
            throw SocketError.socketCreationFailed("Buffer overflow")
        }
        
        return try parseRequest()
    }
    
    private func parseRequest() throws -> HttpRequest? {
        // We need to handle the data in two phases:
        // 1. Parse headers
        // 2. Parse body according to Content-Length
        
        // First, check if we can find the header/body separator
        if isParsingHeaders {
            guard let headerEndRange = buffer.range(of: "\r\n\r\n".data(using: .utf8)!) else {
                // Headers not complete yet
                return nil
            }
            
            // Extract headers
            let headerData = buffer.subdata(in: 0..<headerEndRange.upperBound)
            guard let headerString = String(data: headerData, encoding: .utf8) else {
                throw SocketError.socketCreationFailed("Invalid header encoding")
            }
            
            let headerLines = headerString.components(separatedBy: "\r\n")
            guard headerLines.count >= 1 else {
                return nil
            }
            
            let requestLine = headerLines[0]
            let requestComponents = requestLine.components(separatedBy: " ")
            guard requestComponents.count >= 2 else {
                return nil
            }
            
            // Store the method and path for later use
            currentMethod = requestComponents[0]
            currentPath = requestComponents[1]
            currentHeaders = [:]
            
            // Process headers starting from line 1 (skip the request line)
            for i in 1..<headerLines.count {
                let line = headerLines[i]
                if line.isEmpty {
                    continue
                }
                
                let headerComponents = line.split(separator: ":", maxSplits: 1)
                if headerComponents.count == 2 {
                    let key = String(headerComponents[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(headerComponents[1]).trimmingCharacters(in: .whitespaces)
                    currentHeaders[key] = value
                }
            }
            
            // Get content length
            if let contentLengthStr = currentHeaders["Content-Length"], let length = Int(contentLengthStr) {
                contentLength = length
            }
            
            // Update state
            isParsingHeaders = false
            
            // Remove headers from buffer, leaving only the body part
            buffer.removeSubrange(0..<headerEndRange.upperBound)
            
            // If there's no body expected or we have all the body data, process the request
            if contentLength == 0 || buffer.count >= contentLength {
                let body = contentLength > 0 ? buffer.prefix(contentLength) : nil
                
                // Clean up for the next request
                if contentLength > 0 {
                    buffer.removeSubrange(0..<contentLength)
                }
                isParsingHeaders = true
                
                let request = HttpRequest(
                    method: currentMethod,
                    path: currentPath,
                    headers: currentHeaders,
                    body: body
                )
                
                // Reset state
                contentLength = 0
                currentMethod = ""
                currentPath = ""
                currentHeaders = [:]
                
                return request
            }
            
            // Need more data for the body
            return nil
        } else {
            // We're parsing the body - check if we have enough data
            if buffer.count >= contentLength {
                // We have the complete body
                let body = buffer.prefix(contentLength)
                
                // Create request with stored metadata and body
                let request = HttpRequest(
                    method: currentMethod,
                    path: currentPath,
                    headers: currentHeaders,
                    body: Data(body)
                )
                
                // Clean up for the next request
                buffer.removeSubrange(0..<contentLength)
                isParsingHeaders = true
                
                // Reset state
                contentLength = 0
                currentMethod = ""
                currentPath = ""
                currentHeaders = [:]
                
                return request
            }
            
            // Need more data
            return nil
        }
    }
    
    func supportsKeepAlive(_ headers: [String: String]) -> Bool {
        guard let connection = headers["Connection"]?.lowercased() else {
            return false
        }
        return connection == "keep-alive"
    }
} 
