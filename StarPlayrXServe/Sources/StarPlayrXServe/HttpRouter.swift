//
//  HttpRouter.swift
//  StarPlayrXServe
//
//  Copyright (c) 2025 Todd Bruss. All rights reserved.
//

import Foundation

public typealias dispatchHttpReq = ([String: String], (HttpRequest) -> HttpResponse)

public class HttpRouter {
    private var routeHandlers: [(method: String, path: String, handler: dispatchHttpReq)] = []
    
    public init() {}
    
    public func route(_ method: String, path: String) -> dispatchHttpReq? {
        // First try exact match
        for route in routeHandlers {
            if route.method == method && route.path == path {
                return route.handler
            }
        }
        
        // If not found, try to match pattern with parameters
        for route in routeHandlers {
            let params = matchRoute(route.path, path: path)
            if route.method == method && !params.isEmpty {
                let (routeParams, handler) = route.handler
                var allParams = routeParams
                // Merge route parameters with pattern parameters
                for (key, value) in params {
                    allParams[key] = value
                }
                return (allParams, handler)
            }
        }
        
        return nil
    }
    
    private func matchRoute(_ pattern: String, path: String) -> [String: String] {
        let patternComponents = pattern.components(separatedBy: "/")
        let pathComponents = path.components(separatedBy: "/")
        
        if patternComponents.count != pathComponents.count {
            return [:]
        }
        
        var params: [String: String] = [:]
        
        for i in 0..<patternComponents.count {
            let patternComponent = patternComponents[i]
            let pathComponent = pathComponents[i]
            
            if patternComponent.starts(with: ":") {
                // This is a parameter
                let paramName = String(patternComponent.dropFirst())
                params[paramName] = pathComponent
            } else if patternComponent != pathComponent {
                // Static part doesn't match
                return [:]
            }
        }
        
        return params
    }
    
    public func register(_ method: String, path: String, handler: dispatchHttpReq) {
        routeHandlers.append((method: method, path: path, handler: handler))
    }
    
    public func routes() -> [String] {
        return routeHandlers.map { "\($0.method) \($0.path)" }
    }
} 
