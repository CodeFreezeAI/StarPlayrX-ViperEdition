//
//  HttpRespBodyWriter.swift
//  StarPlayrXServe
//
//  Copyright (c) 2025 Todd Bruss. All rights reserved.
//

import Foundation

public protocol HttpResponseBodyWriter {
    func write(byts data: [UInt8]) throws
    func write(data: Data) throws
} 
