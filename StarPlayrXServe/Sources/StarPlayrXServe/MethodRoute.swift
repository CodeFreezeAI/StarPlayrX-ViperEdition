//
//  MethodRoute.swift
//  StarPlayrXServe
//
//  Copyright (c) 2025 Todd Bruss. All rights reserved.
//

import Foundation

public class MethodRoute {
    private let method: String
    private let router: HttpRouter
    
    public init(method: String, router: HttpRouter) {
        self.method = method
        self.router = router
    }
    
    public func register(_ path: String, handler: dispatchHttpReq) {
        router.register(method, path: path, handler: handler)
    }
    
    public subscript(path: String) -> dispatchHttpReq {
        get {
            router.route(method, path: path) ?? ([:], { _ in HttpResponse.notFound(nil) })
        }
        set {
            router.register(method, path: path, handler: newValue)
        }
    }
} 
