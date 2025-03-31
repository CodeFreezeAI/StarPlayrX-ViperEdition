//
//  HttpRequest.swift
//  StarPlayrXServe
//
//  Copyright (c) 2025 Todd Bruss. All rights reserved.
//

import Foundation

public struct HttpRequest {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data?
    public var params: [String: String] = [:]
    
    public init(method: String, path: String, headers: [String: String], body: Data?) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
} 
