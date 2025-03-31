//
//  File.swift
//  
//
//  Created by Todd Bruss on 9/11/22.
//

import Foundation
import StarPlayrXServe

func pingRoute(pong: String) -> dispatchHttpReq {
    // reset the stream's token id
    resetChTknId = pong

    return ([:], { request in
        return HttpResponse.ok(.ping(pong, contentType: "text/plain"))
    })
}
