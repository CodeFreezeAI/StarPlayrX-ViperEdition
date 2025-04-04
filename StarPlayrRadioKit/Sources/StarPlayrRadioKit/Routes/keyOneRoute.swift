//
//  keyOneRoute.swift
//  StarPlayrRadioApp
//
//  Created by Todd Bruss on 9/5/22.
//

import Foundation
import StarPlayrXServe

func keyOneRoute() -> dispatchHttpReq {
    return ([:], { request in
        guard let data = Data(base64Encoded: userX.key) else {
            return HttpResponse.notFound(.none)
        }
        
        return HttpResponse.ok(.data(data, contentType: "application/octet-stream"))
    })
}
