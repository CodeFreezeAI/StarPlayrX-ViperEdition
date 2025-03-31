//
//  HttpResponse.swift
//  StarPlayrXServe
//
//  Copyright (c) 2025 Todd Bruss. All rights reserved.
//

import Foundation

public struct HttpResponse {
    public let statusCode: Int
    public let reasonPhrase: String
    private let responseHeaders: [String: String]
    private let responseContent: HttpRespBody
    
    public init(statusCode: Int, reasonPhrase: String, headers: [String: String] = [:], content: HttpRespBody) {
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase
        
        var allHeaders = headers
        // Add content-type header if it exists in the HttpRespBody
        if let contentType = content.contentType, allHeaders["Content-Type"] == nil {
            allHeaders["Content-Type"] = contentType
        }
        
        self.responseHeaders = allHeaders
        self.responseContent = content
    }
    
    public func headers() -> [String: String] {
        return responseHeaders
    }
    
    public func content() -> HttpRespBody {
        return responseContent
    }
    
    public static func ok(_ content: HttpRespBody) -> HttpResponse {
        return HttpResponse(statusCode: 200, reasonPhrase: "OK", content: content)
    }
    
    public static func notFound(_ content: HttpRespBody?) -> HttpResponse {
        return HttpResponse(statusCode: 404, reasonPhrase: "Not Found", content: content ?? .empty)
    }
    
    public static func internalServerError(_ content: HttpRespBody?) -> HttpResponse {
        return HttpResponse(statusCode: 500, reasonPhrase: "Internal Server Error", content: content ?? .empty)
    }
} 
