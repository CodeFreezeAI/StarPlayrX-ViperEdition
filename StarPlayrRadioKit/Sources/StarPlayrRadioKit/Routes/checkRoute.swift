//
//  File.swift
//  
//
//  Created by Todd Bruss on 9/11/22.
//

import Foundation
import StarPlayrXServe

func checkRoute(server: HttpServer) -> dispatchHttpReq {
    return ([:], { request in
        // Return a list of all routes
        return HttpResponse.ok(HttpRespBody.json([
            "routes": server.routes
        ]))
    })
}
