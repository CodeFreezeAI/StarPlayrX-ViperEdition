//
//  PlayStream.swift
//  StarPlayr
//
//  Created by Todd on 3/1/19.
//  Copyright © 2019 Todd Bruss. All rights reserved.
//

import Foundation
import StarPlayrRadioKit
import MediaPlayer
import UIKit
import AVFoundation

final class Player: NSObject, AVAssetResourceLoaderDelegate {
    static let shared = Player()
    
    let g = Global.obj
    let pdt = Global.obj.NowPlaying
    
    public let PlayerQueue = DispatchQueue(label: "PlayerQueue", qos: .userInitiated )
    public let PDTqueue = DispatchQueue(label: "PDT", qos: .userInteractive, attributes: .concurrent)
    
    // Simple file logger for debugging when disconnected from Xcode
    struct Logger {
        static let shared = Logger()
        private let fileURL: URL?
        private let dateFormatter: DateFormatter
        private let logQueue = DispatchQueue(label: "com.starplayrx.logger", qos: .background)
        
        init() {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            fileURL = paths.first?.appendingPathComponent("starplayrx_log.txt")
            
            dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            
            // Create or clear log file on startup
            clearLog()
        }
        
        func log(_ message: String) {
            logQueue.async {
                guard let fileURL = self.fileURL else { return }
                let timestamp = self.dateFormatter.string(from: Date())
                let logMessage = "[\(timestamp)] \(message)\n"
                
                if let data = logMessage.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        // Append to existing file
                        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(data)
                            fileHandle.closeFile()
                        }
                    } else {
                        // Create new file
                        try? data.write(to: fileURL)
                    }
                }
                
                // Also print to console for when debugger is attached
                print(logMessage)
            }
        }
        
        func clearLog() {
            logQueue.async {
                guard let fileURL = self.fileURL else { return }
                let header = "--- StarPlayrX Log Started \(self.dateFormatter.string(from: Date())) ---\n"
                try? header.data(using: .utf8)?.write(to: fileURL)
            }
        }
        
        func getLogURL() -> URL? {
            return fileURL
        }
        
        // Get filtered logs that match a specific keyword
        func getFilteredLogs(filter: String? = nil) -> String? {
            guard let fileURL = self.fileURL,
                  let data = try? Data(contentsOf: fileURL),
                  var logString = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            // If filter is provided, only show lines containing that keyword
            if let filter = filter, !filter.isEmpty {
                let lines = logString.components(separatedBy: .newlines)
                let filteredLines = lines.filter { $0.localizedCaseInsensitiveContains(filter) }
                logString = filteredLines.joined(separator: "\n")
            }
            
            return logString
        }
    }
    
    // Log a message both to console and to the log file
    func log(_ message: String) {
        Logger.shared.log(message)
    }
    
    var player = AVQueuePlayer()
    var port: UInt16 = 9999 + 10
    var everything = "All Channels"
    var allStars = "All Stars"
    var SPXPresets = [String]()
    var pdtCache = [String : Any]()
    var localChannelArt = ""
    var localAlbumArt = ""
    var preArtistSong = ""
    var setAlbumArt = false
    var maxAlbumAttempts = 3
    var state : PlayerState = .paused
    var previousHash = "reset"
    let avSession = AVAudioSession.sharedInstance()
    
    // Add connection monitoring and recovery
    private var connectionMonitorTimer: Timer?
    private var heartbeatTimer: Timer?
    private var reconnectionAttempts = 0
    private var maxReconnectionAttempts = 3
    private var lastConnectionActivity = Date()
    
    // MARK: - AVAssetResourceLoaderDelegate
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        // This method is required but we don't need custom resource loading behavior
        // Simply pass through the original requests
        return false
    }
    
    func resetAirPlayVolumeX() {
        if avSession.currentRoute.outputs.first?.portType == .airPlay {
            DispatchQueue.main.async {
                //AP2Volume.shared()?.setVolumeBy(0.0)
            }
        }
    }
    
    func spx(_ state: PlayerState?) {
        if state == .stream {
            if isMacCatalystApp {
                self.resetPlayer()
            }
            self.play()
            self.state = .buffering
        } else if player.rate == 1 || self.state == .playing {
            self.pause()
            self.state = .paused
        } else {
            self.play()
            self.state = .buffering
        }
    }
    
    func new(_ state: PlayerState?) {
        // Update last connection activity time
        self.lastConnectionActivity = Date()
        
        DispatchQueue.global().async { [self] in
            let pinpoint = "\(g.insecure)\(g.localhost):\(port)/api/v3/ping"
            
            log("Checking server connection with ping...")
            Async.api.Text(endpoint: pinpoint, timeOut: 3) { [self] pong in
                guard let ping = pong else { 
                    log("Ping failed, launching server...")
                    launchServer()
                    return 
                }
                
                if ping == "pong" {
                    log("Server connection verified")
                    // Reset reconnection counter on successful ping
                    reconnectionAttempts = 0
                    spx(state)
                } else {
                    log("Server responded with unexpected value: \(ping)")
                    launchServer()
                }
            }
        }
    }
    
    // Start monitoring the connection with regular heartbeats
    private func startConnectionMonitoring() {
        stopConnectionMonitoring() // Clear any existing timers
        
        // Create a timer that checks connection health every 10 seconds
        connectionMonitorTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkConnectionHealth()
        }
        
        // Create a heartbeat timer that logs connection status more frequently
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.logHeartbeat()
        }
    }
    
    // Log connection heartbeat
    private func logHeartbeat() {
        if state == .playing {
            let timeSinceLastActivity = -lastConnectionActivity.timeIntervalSinceNow
            log("HEARTBEAT: Connection active, \(String(format: "%.1f", timeSinceLastActivity))s since last activity")
            
            // Log player status
            if let currentItem = player.currentItem {
                let bufferEmpty = currentItem.isPlaybackBufferEmpty
                let bufferFull = currentItem.isPlaybackLikelyToKeepUp
                let playing = player.rate > 0
                log("HEARTBEAT: Player status - playing: \(playing), buffer empty: \(bufferEmpty), buffer likely to keep up: \(bufferFull)")
            }
        }
    }
    
    // Check if the connection is healthy
    private func checkConnectionHealth() {
        guard state == .playing || state == .buffering else {
            // Only monitor connection when we're supposed to be playing
            return
        }
        
        let timeSinceLastActivity = -lastConnectionActivity.timeIntervalSinceNow
        log("Checking connection health. Time since last activity: \(String(format: "%.1f", timeSinceLastActivity))s")
        
        // If it's been more than 20 seconds since the last activity, check the connection
        if timeSinceLastActivity > 20.0 {
            log("Connection may be stalled, checking server connection")
            checkServerConnection()
        }
    }
    
    // Stop all connection monitoring
    private func stopConnectionMonitoring() {
        connectionMonitorTimer?.invalidate()
        connectionMonitorTimer = nil
        
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        
        reconnectionAttempts = 0
    }
    
    // Check if the server is still responsive
    func checkServerConnection() {
        // Update last activity time to prevent multiple checks in quick succession
        lastConnectionActivity = Date()
        
        log("Checking server connection")
        let pingUrl = "\(g.insecure)\(g.localhost):" + String(port) + "/api/v3/ping"
        
        Async.api.Text(endpoint: pingUrl, timeOut: 3) { [weak self] response in
            guard let self = self else { return }
            
            if let response = response, response == "pong" {
                // Connection is good
                self.log("Server connection check successful - received pong")
                self.lastConnectionActivity = Date()
                self.reconnectionAttempts = 0
                
                // If we're supposed to be playing but aren't, try to resume
                if (self.state == .playing || self.state == .buffering) && self.player.rate == 0 {
                    self.log("Player was stalled but connection is good, resuming playback")
                    self.play()
                }
            } else {
                // Connection issue detected
                self.log("Server connection check failed - no pong response")
                self.handleConnectionIssue()
            }
        }
    }
    
    // Handle connection issues by attempting to reconnect
    private func handleConnectionIssue() {
        if reconnectionAttempts < maxReconnectionAttempts {
            reconnectionAttempts += 1
            log("Attempting server reconnection (\(reconnectionAttempts)/\(maxReconnectionAttempts))")
            
            // Try to relaunch the server
            startServerReconnect()
        } else {
            log("Max reconnection attempts reached, stopping playback")
            stop()
            reconnectionAttempts = 0
            
            // Post notification about connection failure
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .serverConnectionLost, object: nil)
            }
        }
    }
    
    // Launch the server for recovery attempts
    private func startServerReconnect() {
        log("Launching server for reconnection...")
        autoLaunchServer { success in
            if success {
                self.log("Server launched successfully, attempting to reconnect")
                // Wait a moment for the server to fully initialize
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self else { return }
                    
                    if self.state == .playing || self.state == .buffering {
                        self.play()
                    }
                }
            } else {
                self.log("Server launch failed")
                // Notify UI of launch failure
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .serverLaunchFailed, object: nil)
                }
            }
        }
    }
    
    //MARK: Update the screen
    func syncArt() {
        if let sha256 = sha256(String(CACurrentMediaTime().description)) {
            self.previousHash = sha256
        } else {
            let str = "Hello, Last Star Player X."
            self.previousHash = sha256(String(str)) ?? str
        }
        
        if let i = g.ChannelArray.firstIndex(where: {$0.channel == g.currentChannel}) {
            let item = g.ChannelArray[i].largeChannelArtUrl
            self.updateDisplay(key: g.currentChannel, cache: self.pdtCache, channelArt: item, false)
        }
    }
    
    //MARK: Launch Server and Stream
    func launchServer() {
        log("Launching server...")
        autoLaunchServer(){ [weak self] success in
            guard let self = self else { return }
            
            if success {
                self.log("Server launched successfully")
                self.lastConnectionActivity = Date()
                
                // Only restart playback if we were playing before
                if self.state == .playing || self.state == .buffering {
                    self.play()
                }
            } else {
                self.log("Server launch failed")
                self.stop()
                
                // Post notification about server launch failure
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .serverLaunchFailed, object: nil)
                }
            }
        }
    }
    
    //MARK: Stop the player, we have an issue - this could show an interruption
    func stop() {
        self.player.pause()
        self.state = .paused
        NotificationCenter.default.post(name: .didUpdatePause, object: nil)
        self.resetPlayer()
        self.player = AVQueuePlayer()
        
        // Stop connection monitoring when we stop playing
        stopConnectionMonitoring()
        
        log("Player stopped")
    }
    
    func stream() {
        SPXCache() // Cache program data
        
        // Create URL from channel ID
        guard let url = URL(string: "\(g.insecure)\(g.localhost):\(port)/api/v3/m3u/\(g.currentChannel)\(g.m3u8)") else {
            log("Invalid URL")
            return
        }
        
        // Update last activity time
        self.lastConnectionActivity = Date()
        log("Starting stream for channel \(g.currentChannel)")
        
        // Create asset with better configuration
        let assetOptions: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": ["Connection": "keep-alive"],
            "AVURLAssetOutOfBandMIMETypeKey": "application/x-mpegURL"
        ]
        let asset = AVURLAsset(url: url, options: assetOptions)
        
        // Create player item with better settings
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 1
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        
        // Add observers for player item
        NotificationCenter.default.addObserver(self, 
                                              selector: #selector(playerItemFailed(_:)), 
                                              name: .AVPlayerItemFailedToPlayToEndTime, 
                                              object: playerItem)
        
        NotificationCenter.default.addObserver(self, 
                                              selector: #selector(playerItemStalled(_:)), 
                                              name: .AVPlayerItemPlaybackStalled, 
                                              object: playerItem)
        
        let p = self.player
        p.volume = 0
        p.replaceCurrentItem(with: playerItem)
        p.playImmediately(atRate: 1.0)
        p.fadeVolume(from: 0, to: 1, duration: Float(2.5))
        
        // Update state and start monitoring
        state = .playing
        NotificationCenter.default.post(name: .didUpdatePlay, object: nil)
        
        // Update last activity time
        self.lastConnectionActivity = Date()
        
        // Start monitoring connection
        startConnectionMonitoring()
        
        // Log that playback has started
        log("Stream started successfully")
    }
    
    @objc func playerItemFailed(_ notification: Notification) {
        log("Player item failed to play")
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            log("Player error: \(error.localizedDescription)")
        }
        
        // Only try to recover if we should be playing
        if state == .playing || state == .buffering {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.log("Attempting to recover from playback failure")
                self?.checkServerConnection()
            }
        }
    }
    
    @objc func playerItemStalled(_ notification: Notification) {
        log("Player item stalled")
        
        // Only try to recover if we should be playing
        if state == .playing || state == .buffering {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.log("Attempting to recover from playback stall")
                self?.play()
            }
        }
    }
    
    func play() {
        // Update last activity time
        self.lastConnectionActivity = Date()
        log("Starting playback")
        
        let p = self.player
        let currentItem = p.currentItem
        
        var wait = 0.25
        if currentItem == nil {
            wait = 0
        }
        
        p.fadeVolume(from: 1, to: 0, duration: Float(wait))
        state = .buffering
        
        // Configure player item with better settings
        configurePlayerItem(p)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(wait)) { [weak self] in
            self?.stream()
        }
    }
    
    func configurePlayerItem(_ player: AVQueuePlayer) {
        if #available(iOS 13.0, *) {
            player.currentItem?.automaticallyPreservesTimeOffsetFromLive = true
        }

        player.currentItem?.preferredForwardBufferDuration = 0
        player.currentItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.appliesMediaSelectionCriteriaAutomatically = true
        player.allowsExternalPlayback = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + avSession.outputLatency * 2.0) { [weak self] in
            self?.player.currentItem?.preferredForwardBufferDuration = 1
        }
    }
    
    func change() {
        // Update last activity time
        self.lastConnectionActivity = Date()
        
        configurePlayerItem(self.player)
    }
    
    func runReset(starplayrx: AVPlayerItem) {
        // Remove item observers
        NotificationCenter.default.removeObserver(self, 
                                                name: .AVPlayerItemFailedToPlayToEndTime, 
                                                object: starplayrx)
        
        NotificationCenter.default.removeObserver(self, 
                                                name: .AVPlayerItemPlaybackStalled, 
                                                object: starplayrx)
        
        player.replaceCurrentItem(with: nil)
        starplayrx.asset.cancelLoading()
        player.remove(starplayrx)
    }
    
    func resetPlayer() {
        for starplayrx in player.items() {
            runReset(starplayrx: starplayrx)
        }
    }
    
    func pause() {
        self.player.pause()
        self.state = .paused
        NotificationCenter.default.post(name: .didUpdatePause, object: nil)
        self.resetPlayer()
        self.player = AVQueuePlayer()
        
        // Stop connection monitoring when paused
        stopConnectionMonitoring()
    }
    
    //MARK: Update our display
    func updateDisplay(key: String, cache: [String : Any], channelArt: String, _ animated: Bool = true) {
        if let value  = cache[key] as? [String: String],
           let artist = value["artist"] as String?,
           let song   = value["song"] as String?,
           let image  = value["image"] as String?,
           let hash = sha256(artist + song + key + channelArt + image),
           previousHash != hash
        {
            previousHash = hash
            g.NowPlaying = (channel:key,artist:artist,song:song,albumArt:image,channelArt:channelArt, image: nil ) as NowPlayingType
            updateNowPlayingX(animated)
        }
    }
    
    public func chooseFilter(fileName:String, values:[Float],filterKeys:[String],image:UIImage) -> UIImage {
        let context = CIContext()
        let filter = CIFilter(name: fileName)
        for i in 0..<filterKeys.count {
            filter?.setValue(values[i], forKey:filterKeys[i])
        }
        
        filter?.setValue(CIImage(image: image), forKey: kCIInputImageKey)
        
        if let result = filter?.outputImage, let cgimage = context.createCGImage(result, from: result.extent) {
            return UIImage(cgImage: cgimage)
        }
        return image
    }
    
    public func chooseFilterCategories(name:String,values:[Float],filterKeys:[String],image:UIImage) -> UIImage {
        let filters = CIFilter.filterNames(inCategory: name)
        for filter in filters {
            if filter == "CIUnsharpMask" {
                let newImage = self.chooseFilter(fileName: filter, values: values, filterKeys: filterKeys, image: image)
                return newImage
            }
        }
        return image
    }
    
    //loading the album art
    //MARK: Todd
    func updateNowPlayingX(_ animated: Bool = true) {
        let g = Global.obj
        
        func demoImage() -> UIImage? {
            if var img = UIImage(named: "starplayr_placeholder") {
                img = img.withBackground(color: UIColor(displayP3Red: 19 / 255, green: 20 / 255, blue: 36 / 255, alpha: 1.0))
                img = self.resizeImage(image: img, targetSize: CGSize(width: 1440, height: 1440))
                return img
            } else {
                return nil
            }
        }
        
        func displayArt(image: UIImage?) {
            if var img = image {
                img = img.withBackground(color: UIColor(displayP3Red: 19 / 255, green: 20 / 255, blue: 36 / 255, alpha: 1.0))
                
                typealias stepperType = [ (dim: Int, low: Float, high: Float ) ]
                
                let stepper = [ (dim: 720,  low: 0.625, high: 0.125 ),
                                (dim: 1080, low: 0.125, high: 0.25 ),
                                (dim: 1440, low: 0.25,  high: 0.5 )] as stepperType
                
                for x in stepper {
                    //MARK: Resize image
                    img = self.resizeImage(image: img, targetSize: CGSize(width: x.dim, height: x.dim))
                    
                    //MARK: Sharpen image
                    img = self.chooseFilterCategories(name: kCICategorySharpen, values: [x.low,x.high], filterKeys: [kCIInputRadiusKey,kCIInputIntensityKey], image: img)
                }
                
                g.NowPlaying.image = img
                self.setnowPlayingInfo(channel: g.NowPlaying.channel, song: g.NowPlaying.song, artist: g.NowPlaying.artist, imageData:img)
            } else if let i = demoImage() {
                g.NowPlaying.image = i
                self.setnowPlayingInfo(channel: g.NowPlaying.channel, song: g.NowPlaying.song, artist: g.NowPlaying.artist, imageData: i)
            }
            
            if animated {
                DispatchQueue.main.async { NotificationCenter.default.post(name: .gotNowPlayingInfoAnimated, object: nil) }
            } else {
                DispatchQueue.main.async { NotificationCenter.default.post(name: .gotNowPlayingInfo, object: nil) }
            }
        }
        
        //Demo Mode
        if !g.demomode {
            //Get album art
            if g.NowPlaying.albumArt.contains("http") {
                Async.api.Imagineer(endpoint: g.NowPlaying.albumArt, ImageHandler: { (img) -> Void in
                    displayArt(image: img)
                })
            } else {
                //Fix image sizing
                Async.api.Imagineer(endpoint: g.NowPlaying.channelArt, ImageHandler: { (img) -> Void in
                    displayArt(image: img?.addImagePadding(x: 20, y: 200))
                })
            }
        } else {
            if let image = demoImage() {
                displayArt(image: image)
            }
        }
    }

    func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)
        UIGraphicsBeginImageContextWithOptions( targetSize, false, 1.0)
        image.draw(in: rect)
        
        if let newImage = UIGraphicsGetImageFromCurrentImageContext() {
            UIGraphicsEndImageContext()
            return newImage
        }
        return UIImage()
    }
    
    //MARK: Read Write Cache for the PDT (Artist / Song / Album Art)
    @objc func SPXCache() {
        let ps = self
        let gs = g.self
        
        ps.updatePDT() { success in
            if success {
                
                if let i = gs.ChannelArray.firstIndex(where: {$0.channel == gs.currentChannel}) {
                    let item = gs.ChannelArray[i].largeChannelArtUrl
                    ps.updateDisplay(key: gs.currentChannel, cache: ps.pdtCache, channelArt: item)
                }
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .updateChannelsView, object: nil)
                }
            }
        }
    }
    
    //MARK: Update Artist Song Info
    func updatePDT(completionHandler: @escaping CompletionHandler) {
        let g = Global.obj
        let endpoint = g.insecure + g.local + ":" + String(self.port) + "/api/v3/pdt"
        
        Async.api.Get(endpoint: endpoint) { dict in
            if let p = dict as? [String : Any], !p.isEmpty, let cache = p["data"] as? [String : Any], !cache.isEmpty {
                self.pdtCache = cache
                
                g.ChannelArray = self.getPDTData(importData: g.ChannelArray)
                completionHandler(true)
            } else {
                completionHandler(false)
            }
        }
    }
    
    func getPDTData(importData: tableData) -> tableData {
        var nowPlayingData = importData
        
        for i in 0..<nowPlayingData.count {
            let key = nowPlayingData[i].channel
            
            if let value = pdtCache[key] as? [String: String], let artist = value["artist"] as String?, let song = value["song"]  as String?, let image = value["image"]  as String? {
                
                let setArtist = NSMutableAttributedString(string: artist + "\n" , attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 14)]);
                let setSong = NSMutableAttributedString(string: song, attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 14)]);
                
                setArtist.append(setSong)
                nowPlayingData[i].detail = setArtist
                nowPlayingData[i].largeAlbumUrl = image
                nowPlayingData[i].searchString = nowPlayingData[i].title.string
                nowPlayingData[i].searchString = nowPlayingData[i].searchString + " " + artist
                nowPlayingData[i].searchString = nowPlayingData[i].searchString + " " + song
                nowPlayingData[i].searchString = nowPlayingData[i].searchString.replacingOccurrences(of: "'", with: "")
                nowPlayingData[i].image        = nowPlayingData[i].channelImage
                nowPlayingData[i].albumUrl     =  nowPlayingData[i].largeChannelArtUrl
            }
        }
        return nowPlayingData
    }
    
    public func setnowPlayingInfo(channel:String, song:String, artist:String, imageData: UIImage) {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [String: Any]()
        let image = imageData.withBackground(color: UIColor(displayP3Red: 19 / 255, green: 20 / 255, blue: 36 / 255, alpha: 1.0))
        let artwork = MPMediaItemArtwork(boundsSize: image.size, requestHandler: {  (_) -> UIImage in
            return image
        })
        
        nowPlayingInfo[MPMediaItemPropertyTitle]                    = song
        nowPlayingInfo[MPMediaItemPropertyArtist]                   = artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle]               = channel
        nowPlayingInfo[MPMediaItemPropertyPodcastTitle]             = song
        nowPlayingInfo[MPMediaItemPropertyArtwork]                  = artwork
        nowPlayingInfo[MPMediaItemPropertyMediaType]                = 1
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream]        = true
        nowPlayingInfo[MPMediaItemPropertyAlbumArtist]              = artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle]               = g.currentChannelName
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        
        if self.player.rate == 1 {
            if #available(iOS 13.0, *) {
                nowPlayingInfoCenter.playbackState = .playing
            }
        } else {
            if #available(iOS 13.0, *) {
                nowPlayingInfoCenter.playbackState = .paused
            }
        }
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
    }
    
    public func autoLaunchServer(completionHandler: CompletionHandler) {
        print("Restarting Server...")
        
        if UIAccessibility.isVoiceOverRunning {
            let utterance = AVSpeechUtterance(string: "Buffering")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.5
            
            let synthesizer = AVSpeechSynthesizer()
            synthesizer.speak(utterance)
        }
        
        //Find the first Open port
        for i in self.port..<65000 {
            if Network.ability.open(port: UInt16(i)) {
                self.port = UInt16(i)
                break
            }
        }
        startServer(self.port)
        jumpStart()
        
        completionHandler(true)
    }
    
    func magicTapped() {
        new(nil)
    }
    
    ///These are used on the iPhone's lock screen
    ///Command Center routines
    func setupRemoteTransportControls(application: UIApplication) {
        do {
            avSession.accessibilityPerformMagicTap()
            avSession.accessibilityActivate()
            try avSession.setPreferredIOBufferDuration(0)
            try avSession.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [.allowAirPlay])
            try avSession.setActive(true)
            
            // Add interruption observer
            NotificationCenter.default.addObserver(self, 
                                                 selector: #selector(handleAudioInterruption), 
                                                 name: AVAudioSession.interruptionNotification, 
                                                 object: nil)
            
        } catch {
            print("Audio session error: \(error)")
        }
        
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.accessibilityActivate()
        
        // Clear existing handlers first to avoid duplicates
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("Remote command: Play")
            self.new(.stream)
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("Remote command: Pause")
            self.new(.paused)
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("Remote command: Toggle")
            self.new(nil)
            return .success
        }
    }
    
    @objc func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Interruption began, update state but don't change playback yet
            log("Audio session interrupted")
            if state == .playing {
                // Remember we were playing, but don't change state yet
                player.pause()
            }
            
        case .ended:
            // Interruption ended - check if we should resume
            log("Audio interruption ended")
            
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    log("Should resume after interruption")
                    
                    // Check server connection before resuming
                    checkServerConnection()
                }
            }
            
        @unknown default:
            break
        }
    }
}

func jumpStart() {
    let net = Network.ability
    net.start()
    let locale = Locale.current
    
    if locale.regionCode == "CA" || locale.regionCode == "CAN" {
        preflightConfig(location: "CA")
    } else {
        preflightConfig(location: "US")
    }
}

// Add new notification names
extension Notification.Name {
    static let serverConnectionLost = Notification.Name("serverConnectionLost")
    static let serverLaunchFailed = Notification.Name("serverLaunchFailed")
}
