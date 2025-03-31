//
//  main.swift
//  StarPlayrXServe
//
//  Copyright (c) 2024 Todd Bruss. All rights reserved.
//

import Foundation
import StarPlayrXServe

// Create server instance
let server = HttpServer()

// Basic route handlers
server.get["/"] = ([:], { request in
    return HttpResponse.ok(HttpRespBody.ping("Welcome to StarPlayrXServe!\n\nAvailable routes:\n/ - This message\n/hello - Hello World\n/api/v3/routes - Show all routes"))
})

server.get["/hello"] = ([:], { request in
    return HttpResponse.ok(HttpRespBody.ping("Hello, World!"))
})

// Example route handlers with parameters
func pingRoute(pong: String) -> dispatchHttpReq {
    return ([:], { request in
        return HttpResponse.ok(HttpRespBody.json(["ping": pong]))
    })
}

func regionRoute(region: String) -> dispatchHttpReq {
    return ([:], { request in
        return HttpResponse.ok(HttpRespBody.json(["region": region]))
    })
}

func loginRoute() -> dispatchHttpReq {
    return ([:], { request in
        // Simulate processing login data
        var response: [String: Any] = [
            "success": true,
            "session": "example-session-token-123",
            "expires": Date().timeIntervalSince1970 + 3600
        ]
        
        if let body = request.body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let username = json["username"] as? String {
            response["username"] = username
        }
        
        return HttpResponse.ok(HttpRespBody.json(response))
    })
}

func sessionRoute() -> dispatchHttpReq {
    return ([:], { request in
        // Simulate session validation
        return HttpResponse.ok(HttpRespBody.json([
            "valid": true,
            "remaining": 3600
        ]))
    })
}

func channelsRoute() -> dispatchHttpReq {
    return ([:], { request in
        // Simulate returning channels
        return HttpResponse.ok(HttpRespBody.json([
            "channels": [
                ["id": "ch1", "name": "Channel 1"],
                ["id": "ch2", "name": "Channel 2"],
                ["id": "ch3", "name": "Channel 3"]
            ]
        ]))
    })
}



func keyOneRoute() -> dispatchHttpReq {
    return ([:], { request in
        return HttpResponse.ok(HttpRespBody.json([
            "key": "example-api-key-123"
        ]))
    })
}

func playlistRoute() -> dispatchHttpReq {
    return ([:], { request in
        // Get channel ID from request parameters
        let channelId = request.params["channelid"] ?? "unknown"
        
        // Generate a simple M3U playlist
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720
        /api/v3/aac/\(channelId)-hd
        #EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=854x480
        /api/v3/aac/\(channelId)-sd
        """
        
        return HttpResponse.ok(HttpRespBody.ping(playlist, contentType: "application/x-mpegURL"))
    })
}



func checkRoute(server: HttpServer) -> dispatchHttpReq {
    return ([:], { request in
        // Return a list of all routes
        return HttpResponse.ok(HttpRespBody.json([
            "routes": server.routes
        ]))
    })
}

// Register the routes
server.get["/api/v3/ping"] = pingRoute(pong: "pong")
server.get["/api/v3/us"] = regionRoute(region: "us")
server.get["/api/v3/ca"] = regionRoute(region: "ca")
server.post["/api/v3/login"] = loginRoute()
server.post["/api/v3/session"] = sessionRoute()
server.post["/api/v3/channels"] = channelsRoute()
server.get["/api/v3/pdt"] = pdtRoute()
server.get["/api/v3/key"] = keyOneRoute()
server.get["/api/v3/m3u/:channelid"] = playlistRoute()
server.get["/api/v3/aac/:aac"] = audioRoute()
server.get["/api/v3/routes"] = checkRoute(server: server)

// Start server
do {
    // Try a list of ports in case some are already in use
    let ports = [0, 10104, 10105, 10106, 10107, 10108, 10109, 10110]
    var server_port: in_port_t = 0
    var started = false
    
    for port in ports {
        do {
            server_port = in_port_t(port)
            try server.start(server_port)
            started = true
            break
        } catch {
            print("Port \(port) is unavailable. Trying next port...")
            continue
        }
    }
    
    if !started {
        print("Failed to start server on any port. All ports are in use.")
        exit(1)
    }
    
    // Get the actual port that was assigned
    let actualPort = try server.port()
    print("Server started on port \(actualPort)")
    print("Visit http://localhost:\(actualPort)/ for available routes")
    
    // Keep the server running
    RunLoop.main.run()
} catch {
    print("Failed to start server: \(error)")
} 
