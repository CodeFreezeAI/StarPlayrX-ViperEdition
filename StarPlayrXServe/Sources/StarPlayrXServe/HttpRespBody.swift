//
//  HttpRespBody.swift
//  StarPlayrXServe
//
//  Copyright (c) 2025 Todd Bruss. All rights reserved.
//

import Foundation

public enum HttpRespBody {
    case json(Any,     contentType: String? = "application/json")
    case ping(String,  contentType: String? = "text/plain")
    case data(Data,    contentType: String? = nil)
    case byts([UInt8], contentType: String? = nil)
    case empty
    
    public var length: Int {
        switch self {
        case .json(let object, _):
            if let data = try? JSONSerialization.data(withJSONObject: object) {
                return data.count
            }
            return 0
        case .ping(let string, _):
            return string.utf8.count
        case .data(let data, _):
            return data.count
        case .byts(let bytes, _):
            return bytes.count
        case .empty:
            return 0
        }
    }
    
    public var contentType: String? {
        switch self {
        case .json(_, let contentType):
            return contentType
        case .ping(_, let contentType):
            return contentType
        case .data(_, let contentType):
            return contentType
        case .byts(_, let contentType):
            return contentType
        case .empty:
            return nil
        }
    }
    
    public var write: ((HttpResponseBodyWriter) throws -> Void)? {
        switch self {
        case .json(let object, _):
            return { writer in
                let data = try JSONSerialization.data(withJSONObject: object)
                try writer.write(data: data)
            }
        case .ping(let string, _):
            return { writer in
                try writer.write(byts: [UInt8](string.utf8))
            }
        case .data(let data, _):
            return { writer in
                try writer.write(data: data)
            }
        case .byts(let bytes, _):
            return { writer in
                try writer.write(byts: bytes)
            }
        case .empty:
            return nil
        }
    }
    
    // Helper methods for common use cases
    public static func makeString(_ string: String, contentType: String? = "text/plain") -> HttpRespBody {
        return .ping(string, contentType: contentType)
    }
    
    public static func makeJson(_ object: Any) -> HttpRespBody {
        return .json(object)
    }
} 
