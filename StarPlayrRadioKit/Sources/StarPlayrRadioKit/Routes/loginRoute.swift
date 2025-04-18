//
//  Login.swift
//  StarPlayrRadioApp
//
//  Created by Todd Bruss on 9/5/22.
//

import Foundation
import StarPlayrXServe

func loginRoute() -> dispatchHttpReq {
    return ([:], { request in
        print(request.body!)
            let json = try? JSONSerialization.jsonObject(with: Data(request.body ?? Data()), options: JSONSerialization.ReadingOptions.fragmentsAllowed) as? [String : Any]
            var obj = [String : Any]()
            guard
                let user = json?["user"] as? String,
                let pass = json?["pass"] as? String
            else {
                let object = ["data": "Failed to login.", "message": "Login failure.", "success": false] as [String : Any]
                if let data = try? JSONSerialization.data(withJSONObject: object) {
                    return HttpResponse.ok(.data(data, contentType: "application/json"))
                }
                
                // return blank if nothing to return
                return HttpResponse.ok(.data(Data(), contentType: "application/json"))
            }
            
            
            let login = LoginX(username: user, pass: pass)
            PostSync(request: login.request, endpoint: login.endpoint, method: login.method) { result in
                
                guard
                    let result = result
                else {
                    return
                }
                
                let returnData = processLogin(username: user, pass: pass, result: result)
                
                if returnData.success {
                    storeCookiesX()
                }
                
                obj = ["data": returnData.data, "message": returnData.message, "success": returnData.success] as [String : Any]
            }
            return HttpResponse.ok(.json(obj))
    })
}
