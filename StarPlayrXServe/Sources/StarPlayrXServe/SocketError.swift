//
//  SocketError.swift
//  StarPlayrXServe
//
//  Copyright (c) 2025 Todd Bruss. All rights reserved.
//

import Foundation

public enum SocketError: Error {
    case socketCreationFailed(String)
    case socketConnectionFailed(String)
    case socketWriteFailed(String)
    case socketReadFailed(String)
} 
