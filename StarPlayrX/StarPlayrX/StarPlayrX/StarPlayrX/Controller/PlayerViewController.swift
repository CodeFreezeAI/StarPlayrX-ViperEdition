//
//  Player.swift
//  StarPlayrX
//
//  Created by Todd on 2/9/19.
//  Copyright © 2019 Todd Bruss. All rights reserved.
//

import UIKit
import AVKit
import MediaPlayer

class PlayerViewController: UIViewController, AVRoutePickerViewDelegate  {
    
    let g = Global.obj
    
#if !targetEnvironment(simulator)
    let ap2volume = GTCola.shared()
#else
    let ap2volume: ()? = nil
#endif
    
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
    override var prefersHomeIndicatorAutoHidden : Bool { return true }
    
    @IBOutlet weak var mainView: UIView!
    
    //UI Variables
    weak var PlayerView   : UIView!
    weak var AlbumArt     : UIImageView!
    weak var Artist       : UILabel?
    weak var Song         : UILabel?
    weak var ArtistSong   : UILabel?
    weak var VolumeSlider : UISlider!
    weak var PlayerXL     : UIButton!
    weak var SpeakerView  : UIImageView!
    
    var playerViewTimerX = Timer()
    var volumeTimer = Timer()
    
    var AirPlayView      = UIView()
    var AirPlayBtn       = AVRoutePickerView()
    var allStarButton    = UIButton(type: UIButton.ButtonType.custom)
    
    var currentSpeaker = Speakers.speaker0
    var previousSpeaker = Speakers.speaker3
    
    //other variables
    var channelString = "Channels"
    
    //Art Queue
    public let ArtQueue = DispatchQueue(label: "ArtQueue", qos: .background )
    
    // Add status indicator for visual feedback
    private var statusLabel: UILabel?
    private var statusFadeTimer: Timer?
    private var connectionCheckButton: UIButton?
    private var debugLogButton: UIButton?
    var isMacCatalystApp = false
    
    // Create a status indicator to show connection status
    private func setupStatusIndicator() {
        // Create status label
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0, alpha: 0.7)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.alpha = 0
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        mainView.addSubview(label)
        
        // Position it at the bottom of the screen
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: mainView.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: mainView.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            label.widthAnchor.constraint(lessThanOrEqualTo: mainView.widthAnchor, constant: -40),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
        
        statusLabel = label
        
        // Add a manual connection check button (debug only)
        #if DEBUG
        let button = UIButton(type: .system)
        button.setTitle("Check Connection", for: .normal)
        button.backgroundColor = UIColor(white: 0, alpha: 0.7)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        button.alpha = 0.8
        button.addTarget(self, action: #selector(checkConnection), for: .touchUpInside)
        mainView.addSubview(button)
        
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: mainView.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -10),
            button.widthAnchor.constraint(lessThanOrEqualTo: mainView.widthAnchor, constant: -40),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        
        connectionCheckButton = button
        #endif
        
        // Add logs button (available in all builds)
        let logButton = UIButton(type: .system)
        logButton.setTitle("View Logs", for: .normal)
        logButton.backgroundColor = UIColor(white: 0, alpha: 0.7)
        logButton.setTitleColor(.white, for: .normal)
        logButton.layer.cornerRadius = 10
        logButton.clipsToBounds = true
        logButton.alpha = 0.8
        logButton.addTarget(self, action: #selector(viewLogs), for: .touchUpInside)
        mainView.addSubview(logButton)
        
        logButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logButton.trailingAnchor.constraint(equalTo: mainView.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            logButton.topAnchor.constraint(equalTo: mainView.safeAreaLayoutGuide.topAnchor, constant: 10),
            logButton.widthAnchor.constraint(equalToConstant: 90),
            logButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        debugLogButton = logButton
    }
    
    @objc private func checkConnection() {
        showStatus("Checking connection...")
        Player.shared.checkServerConnection()
    }
    
    @objc private func viewLogs() {
        // Present logs view
        let logsVC = UIViewController()
        logsVC.title = "Connection Logs"
        
        // Set background color to match app theme
        logsVC.view.backgroundColor = UIColor(displayP3Red: 19/255, green: 20/255, blue: 36/255, alpha: 1.0)
        
        // Create a text view to show logs
        let textView = UITextView()
        textView.isEditable = false
        textView.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
        textView.textColor = .white
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.contentInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        // Create a filter segment control
        let filterSegment = UISegmentedControl(items: ["All Logs", "Heartbeat"])
        filterSegment.selectedSegmentIndex = 0
        filterSegment.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        if #available(iOS 13.0, *) {
            filterSegment.selectedSegmentTintColor = UIColor.systemBlue
        }
        filterSegment.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        filterSegment.translatesAutoresizingMaskIntoConstraints = false
        filterSegment.addTarget(self, action: #selector(filterLogsChanged(_:)), for: .valueChanged)
        
        logsVC.view.addSubview(filterSegment)
        logsVC.view.addSubview(textView)
        
        NSLayoutConstraint.activate([
            filterSegment.topAnchor.constraint(equalTo: logsVC.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            filterSegment.leadingAnchor.constraint(equalTo: logsVC.view.leadingAnchor, constant: 16),
            filterSegment.trailingAnchor.constraint(equalTo: logsVC.view.trailingAnchor, constant: -16),
            filterSegment.heightAnchor.constraint(equalToConstant: 32),
            
            textView.topAnchor.constraint(equalTo: filterSegment.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: logsVC.view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: logsVC.view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: logsVC.view.safeAreaLayoutGuide.bottomAnchor, constant: -44)
        ])
        
        // Add a toolbar with refresh and share buttons
        let toolbar = UIToolbar()
        toolbar.barStyle = .black
        toolbar.isTranslucent = true
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        logsVC.view.addSubview(toolbar)
        
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: logsVC.view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: logsVC.view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: logsVC.view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        let refreshButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshLogs(_:)))
        let clearButton = UIBarButtonItem(title: "Clear", style: .plain, target: self, action: #selector(clearLogs(_:)))
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareLogs(_:)))
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        toolbar.items = [refreshButton, flexSpace, clearButton, flexSpace, shareButton]
        
        // Try to read log file
        if let logString = Player.Logger.shared.getFilteredLogs() {
            textView.text = logString
            // Scroll to bottom
            if logString.count > 0 {
                let bottom = NSRange(location: logString.count - 1, length: 1)
                textView.scrollRangeToVisible(bottom)
            }
        } else {
            textView.text = "No logs available"
        }
        
        // Show loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        logsVC.view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: logsVC.view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: logsVC.view.centerYAnchor)
        ])
        
        activityIndicator.startAnimating()
        
        // Present the logs view controller
        let navController = UINavigationController(rootViewController: logsVC)
        navController.navigationBar.barStyle = .black
        navController.navigationBar.tintColor = .white
        if #available(iOS 13.0, *) {
            navController.modalPresentationStyle = .automatic
        } else {
            navController.modalPresentationStyle = .fullScreen
        }
        
        // Add close button
        let closeButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissLogs))
        logsVC.navigationItem.rightBarButtonItem = closeButton
        
        // Save text view and segment control references
        objc_setAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 1)!, textView, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 2)!, activityIndicator, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 3)!, filterSegment, .OBJC_ASSOCIATION_RETAIN)
        
        present(navController, animated: true) {
            activityIndicator.stopAnimating()
        }
    }
    
    @objc private func filterLogsChanged(_ sender: UISegmentedControl) {
        guard let logsVC = (presentedViewController as? UINavigationController)?.topViewController,
              let textView = objc_getAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 1)!) as? UITextView,
              let activityIndicator = objc_getAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 2)!) as? UIActivityIndicatorView else {
            return
        }
        
        activityIndicator.startAnimating()
        
        DispatchQueue.global().async {
            // Get filter based on segment selection
            let filter = sender.selectedSegmentIndex == 1 ? "HEARTBEAT" : nil
            
            // Get filtered logs
            let logString = Player.Logger.shared.getFilteredLogs(filter: filter) ?? "No logs available"
            
            DispatchQueue.main.async {
                textView.text = logString
                
                // Scroll to bottom
                if logString.count > 0 {
                    let bottom = NSRange(location: logString.count - 1, length: 1)
                    textView.scrollRangeToVisible(bottom)
                }
                
                activityIndicator.stopAnimating()
            }
        }
    }
    
    @objc private func clearLogs(_ sender: UIBarButtonItem) {
        // Clear log file and update display
        Player.Logger.shared.clearLog()
        
        // Get the logs view controller and refresh
        if let navController = presentedViewController as? UINavigationController,
           let logsVC = navController.topViewController,
           let textView = objc_getAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 1)!) as? UITextView,
           let activityIndicator = objc_getAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 2)!) as? UIActivityIndicatorView {
            
            activityIndicator.startAnimating()
            
            // Update logs
            DispatchQueue.global().async {
                if let logURL = Player.Logger.shared.getLogURL(),
                   let logData = try? Data(contentsOf: logURL),
                   let logString = String(data: logData, encoding: .utf8) {
                    
                    DispatchQueue.main.async {
                        textView.text = logString
                        // Scroll to bottom
                        if logString.count > 0 {
                            let bottom = NSRange(location: logString.count - 1, length: 1)
                            textView.scrollRangeToVisible(bottom)
                        }
                        activityIndicator.stopAnimating()
                        
                        // Show a success message
                        let alertController = UIAlertController(
                            title: "Logs Cleared",
                            message: "The log file has been cleared successfully.",
                            preferredStyle: .alert
                        )
                        
                        alertController.addAction(UIAlertAction(title: "OK", style: .default))
                        logsVC.present(alertController, animated: true)
                    }
                }
            }
        }
    }
    
    @objc private func dismissLogs() {
        dismiss(animated: true)
    }
    
    @objc private func refreshLogs(_ sender: UIBarButtonItem) {
        // Get the logs view controller
        if let navController = presentedViewController as? UINavigationController,
           let logsVC = navController.topViewController,
           let textView = objc_getAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 1)!) as? UITextView,
           let activityIndicator = objc_getAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 2)!) as? UIActivityIndicatorView,
           let filterSegment = objc_getAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 3)!) as? UISegmentedControl {
            
            activityIndicator.startAnimating()
            
            // Update logs
            DispatchQueue.global().async {
                // Get filter based on segment selection
                let filter = filterSegment.selectedSegmentIndex == 1 ? "HEARTBEAT" : nil
                
                // Get filtered logs
                let logString = Player.Logger.shared.getFilteredLogs(filter: filter) ?? "No logs available"
                
                DispatchQueue.main.async {
                    textView.text = logString
                    
                    // Scroll to bottom
                    if logString.count > 0 {
                        let bottom = NSRange(location: logString.count - 1, length: 1)
                        textView.scrollRangeToVisible(bottom)
                    }
                    
                    activityIndicator.stopAnimating()
                }
            }
        }
    }
    
    @objc private func shareLogs(_ sender: UIBarButtonItem) {
        if let navController = presentedViewController as? UINavigationController,
           let logsVC = navController.topViewController,
           let activityIndicator = objc_getAssociatedObject(logsVC, UnsafeRawPointer(bitPattern: 2)!) as? UIActivityIndicatorView {
            
            activityIndicator.startAnimating()
            
            if let logURL = Player.Logger.shared.getLogURL() {
                // Ensure the file exists and has content
                if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
                   let fileSize = attrs[.size] as? UInt64, fileSize > 0 {
                    
                    let activityVC = UIActivityViewController(activityItems: [logURL], applicationActivities: nil)
                    
                    // Present from the button on iPad
                    if let popover = activityVC.popoverPresentationController {
                        popover.barButtonItem = sender
                    }
                    
                    logsVC.present(activityVC, animated: true) {
                        activityIndicator.stopAnimating()
                    }
                } else {
                    activityIndicator.stopAnimating()
                    
                    // Show alert for empty logs
                    let alertController = UIAlertController(
                        title: "Empty Logs",
                        message: "The log file is empty or cannot be accessed.",
                        preferredStyle: .alert
                    )
                    
                    alertController.addAction(UIAlertAction(title: "OK", style: .default))
                    logsVC.present(alertController, animated: true)
                }
            } else {
                activityIndicator.stopAnimating()
                
                // Show alert for missing log file
                let alertController = UIAlertController(
                    title: "No Log File",
                    message: "Could not locate the log file.",
                    preferredStyle: .alert
                )
                
                alertController.addAction(UIAlertAction(title: "OK", style: .default))
                logsVC.present(alertController, animated: true)
            }
        }
    }
    
    // Show a status message that fades after a delay
    private func showStatus(_ message: String, duration: TimeInterval = 3.0) {
        guard let statusLabel = statusLabel else { return }
        
        // Cancel any existing fade timer
        statusFadeTimer?.invalidate()
        
        DispatchQueue.main.async {
            // Add padding to the message
            statusLabel.text = "  \(message)  "
            
            // Fade in
            UIView.animate(withDuration: 0.3) {
                statusLabel.alpha = 1.0
            }
            
            // Set timer to fade out
            self.statusFadeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {  _ in
                UIView.animate(withDuration: 0.3) {
                    statusLabel.alpha = 0
                }
            }
        }
    }
    
    func Pulsar() {
        let pulseAnimation = CABasicAnimation(keyPath: "opacity")
        pulseAnimation.duration = 2
        pulseAnimation.fromValue = 1
        pulseAnimation.toValue = 0.25
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .greatestFiniteMagnitude
        
        self.AirPlayView.layer.add(pulseAnimation, forKey: nil)
    }
    
    func noPulsar() {
        self.AirPlayView.layer.removeAllAnimations()
    }
    
    func PulsarAnimation(tune: Bool = false) {
        if Player.shared.avSession.currentRoute.outputs.first?.portType == .airPlay {
            Pulsar()
            
            if tune {
                Player.shared.change()
            }
            
        } else {
            noPulsar()
            
            if tune {
                Player.shared.change()
            }
        }
    }
    
    func startVolumeTimer() {
        invalidateTimer()
        self.playerViewTimerX = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(volumeChanged), userInfo: nil, repeats: true)
    }
    
    func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        volumeChanged()
        startVolumeTimer()
        PulsarAnimation(tune: true)
    }
    
    func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        invalidateTimer()
        volumeChanged()
        PulsarAnimation(tune: true)
    }
    
    func checkForAllStar() {
        let data = g.ChannelArray
        
        for c in data {
            if c.channel == g.currentChannel {
                if c.preset {
                    allStarButton.setImage(UIImage(named: "star_on"), for: .normal)
                    allStarButton.accessibilityLabel = "Preset On, Channel \(g.currentChannelName)"
                } else {
                    allStarButton.setImage(UIImage(named: "star_off"), for: .normal)
                    allStarButton.accessibilityLabel = "Preset Off."
                    
                }
                break
            }
        }
    }
    
    override func loadView() {
        super.loadView()
        
        if #available(iOS 13.0, *) {
            isMacCatalystApp = ProcessInfo.processInfo.isMacCatalystApp
        }
        
        var isPhone = true
        var NavY = CGFloat(0)
        var TabY = CGFloat(0)
        
        //MARK: Draws out main Player View object : visible "Safe Area" only - calculated
        if let navY = self.navigationController?.navigationBar.frame.size.height,
           let tabY = self.tabBarController?.tabBar.frame.size.height {
            
            NavY = navY
            TabY = tabY
            isPhone = true
            
        } else if let tabY = self.tabBarController?.tabBar.frame.size.height {
            
            NavY = 0
            TabY = tabY
            isPhone = false
        }
        
        drawPlayer(frame: mainView.frame, isPhone: isPhone, NavY: NavY, TabY: TabY)
        setupStatusIndicator()
    }
    
    func drawPlayer(frame: CGRect, isPhone: Bool, NavY: CGFloat, TabY: CGFloat) {
        //Instantiate draw class
        let draw = Draw(frame: frame, isPhone: isPhone, NavY: NavY, TabY: TabY)
        
        
        //MARK: 1 - PlayerView must run 1st
        PlayerView = draw.PlayerView(mainView: mainView)
        
        if let pv = PlayerView {
            AlbumArt = draw.AlbumImageView(playerView: pv)
            
            if isPhone {
                let artistSongLabelArray = draw.ArtistSongiPhone(playerView: pv)
                Artist = artistSongLabelArray[0]
                Song   = artistSongLabelArray[1]
            } else {
                ArtistSong = draw.ArtistSongiPad(playerView: pv)
            }
            
            VolumeSlider = draw.VolumeSliders(playerView: pv)
            addSliderAction()
            
            PlayerXL = draw.PlayerButton(playerView: pv)
            PlayerXL.addTarget(self, action: #selector(PlayPause), for: .touchUpInside)
            PlayerXL.accessibilityLabel = "Play Pause"
            SpeakerView = draw.SpeakerImage(playerView: pv)
            updatePlayPauseIcon(play: true)
            setAllStarButton()
            
            //#if !targetEnvironment(simulator)
            let vp = draw.AirPlay(airplayView: AirPlayView, playerView: pv)
            
            AirPlayBtn = vp.picker
            AirPlayView = vp.view
            //#endif
        }
    }
    
    func startupVolume() {
    #if targetEnvironment(simulator)
        runSimulation()
    #else
        if !g.demomode && !isMacCatalystApp {
            if let ap2 = ap2volume {
                ap2.hud(false) //Disable HUD on this view
                volumeChanged()
                setSpeakers(value: ap2.getSoda())
            } else {
                runSimulation()
            }
        }
    #endif
    }
    
    func shutdownVolume() {
    #if !targetEnvironment(simulator)
        if !g.demomode && !isMacCatalystApp {
            ap2volume?.hud(true) //Enable HUD on this view
        }
    #endif
    }
    
    @objc func OnDidUpdatePlay(){
        DispatchQueue.main.async {
            self.updatePlayPauseIcon(play: true)
        }
    }
    
    @objc func OnDidUpdatePause(){
        DispatchQueue.main.async {
            self.updatePlayPauseIcon(play: false)
        }
    }
    
    func setObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(OnDidUpdatePlay), name: .didUpdatePlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(OnDidUpdatePause), name: .didUpdatePause, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(GotNowPlayingInfoAnimated), name: .gotNowPlayingInfoAnimated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(GotNowPlayingInfo), name: .gotNowPlayingInfo, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: .willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleServerConnectionLost), name: .serverConnectionLost, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleServerLaunchFailed), name: .serverLaunchFailed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlayerItemStalled), name: .AVPlayerItemPlaybackStalled, object: nil)
        startObservingVolumeChanges()
    }
    
    func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .didUpdatePlay, object: nil)
        NotificationCenter.default.removeObserver(self, name: .didUpdatePause, object: nil)
        NotificationCenter.default.removeObserver(self, name: .gotNowPlayingInfoAnimated, object: nil)
        NotificationCenter.default.removeObserver(self, name: .gotNowPlayingInfo, object: nil)
        NotificationCenter.default.removeObserver(self, name: .willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .serverConnectionLost, object: nil)
        NotificationCenter.default.removeObserver(self, name: .serverLaunchFailed, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: nil)
        stopObservingVolumeChanges()
    }
    //MARK: End Observers
    
    //MARK: Update Play Pause Icon
    func updatePlayPauseIcon(play: Bool? = nil) {
        
        switch play {
        case .none :
            
            Player.shared.state == PlayerState.playing ?
            self.PlayerXL.setImage(UIImage(named: "pause_button"), for: .normal) :
            self.PlayerXL.setImage(UIImage(named: "play_button"), for:  .normal)
            
        case .some(true) :
            
            self.PlayerXL.setImage(UIImage(named: "pause_button"), for: .normal)
            
        case .some(false) :
            self.PlayerXL.setImage(UIImage(named: "play_button"), for: .normal)
        }
    }
    
    func setAllStarButton() {
        allStarButton.setImage(UIImage(named: "star_off"), for: .normal)
        allStarButton.accessibilityLabel = "Star"
        allStarButton.addTarget(self, action:#selector(AllStarX), for: .touchUpInside)
        allStarButton.frame = CGRect(x: 0, y: 0, width: 35, height: 35)
        let barButton = UIBarButtonItem(customView: allStarButton)
        
        self.navigationItem.rightBarButtonItem = barButton
        self.navigationItem.rightBarButtonItem?.tintColor = .systemBlue
        checkForAllStar()
    }
    
    @objc func AllStarX() {
        let sp = Player.shared
        sp.SPXPresets = [String]()
        
        var index = -1
        for d in g.ChannelArray {
            index = index + 1
            if d.channel == g.currentChannel {
                g.ChannelArray[index].preset = !g.ChannelArray[index].preset
                
                if g.ChannelArray[index].preset {
                    allStarButton.setImage(UIImage(named: "star_on"), for: .normal)
                    allStarButton.accessibilityLabel = "Preset On, Channel \(g.currentChannelName)"
                    
                } else {
                    allStarButton.setImage(UIImage(named: "star_off"), for: .normal)
                    allStarButton.accessibilityLabel = "Preset Off."
                }
            }
            
            if g.ChannelArray[index].preset {
                sp.SPXPresets.append(d.channel)
            }
        }
        
        if !sp.SPXPresets.isEmpty {
            UserDefaults.standard.set(sp.SPXPresets, forKey: "SPXPresets")
        }
    }
    
    //MARK: Magic tap for the rest of us
    @objc func doubleTapped() {
        PlayPause()
    }
    
    func doubleTap() {
        //Pause Gesture
        let doubleFingerTapToPause = UITapGestureRecognizer(target: self, action: #selector(self.doubleTapped) )
        doubleFingerTapToPause.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleFingerTapToPause)
    }
    
    func runSimulation() {
        let value = Player.shared.player.volume
        //value = value == 0.0 ? 1.0 : value
        VolumeSlider.setValue(value, animated: true)
        self.setSpeakers(value: value)
    }
    
    @objc func volumeChanged() {
        if VolumeSlider.isTracking { return }
        
    #if !targetEnvironment(simulator)
        if !g.demomode && !isMacCatalystApp, let ap2 = Player.shared.avSession.outputVolume as Float?  {
            DispatchQueue.main.async {
                self.VolumeSlider.setValue(ap2, animated: true)
                self.setSpeakers(value: ap2)
            }
        }
    #endif
    }
    
    private struct Observation {
        static let VolumeKey = "outputVolume"
        static var Context = 0
        
    }
    
    func startObservingVolumeChanges() {
        Player.shared.avSession.addObserver(self, forKeyPath: Observation.VolumeKey, options: [.initial, .new], context: &Observation.Context)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if VolumeSlider.isTracking { return }
        
        if context == &Observation.Context {
            if keyPath == Observation.VolumeKey, let volume = (change?[NSKeyValueChangeKey.newKey] as? NSNumber)?.floatValue {
                self.VolumeSlider.setValue(volume, animated: true)
                
            }
        }
    }
    
    func stopObservingVolumeChanges() {
        Player.shared.avSession.removeObserver(self, forKeyPath: Observation.VolumeKey, context: &Observation.Context)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        updatePlayPauseIcon()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setObservers()
        doubleTap()
        AirPlayBtn.delegate = self
        
    #if targetEnvironment(simulator)
        runSimulation()
    #endif
        
        if self.g.demomode {
            runSimulation()
        }
        restartPDT()
        
    #if !targetEnvironment(simulator)
        volumeChanged()
    #endif
        checkForNetworkError()
    }
    
    @objc func GotNowPlayingInfoAnimated() {
        GotNowPlayingInfo(true)
    }
    
    @objc func GotNowPlayingInfo(_ animated: Bool = true) {
        let pdt = g.NowPlaying
        
        func accessibility() {
            Artist?.accessibilityLabel = pdt.artist + ". " + pdt.song + "."
            ArtistSong?.accessibilityLabel = pdt.artist + ". " + pdt.song + "."
            Song?.accessibilityLabel = ""
            Song?.accessibilityHint = ""
        }
        
        func staticArtistSong() -> Array<(lbl: UILabel?, str: String)> {
            let combo  = pdt.artist + " • " + pdt.song + " — " + g.currentChannelName
            let artist = pdt.artist
            let song   = pdt.song
            
            let combine = [
                ( lbl: self.Artist,     str: artist ),
                ( lbl: self.Song,       str: song ),
                ( lbl: self.ArtistSong, str: combo ),
            ]
            
            return combine
        }
        
        accessibility()
        let labels = staticArtistSong()
        
        self.AlbumArt.layer.shadowOpacity = 1.0
        
        func presentArtistSongAlbumArt(_ artist: UILabel, duration: Double) {
            DispatchQueue.main.async {
                UIView.transition(with: self.AlbumArt,
                                  duration:duration,
                                  options: .transitionCrossDissolve,
                                  animations: { _ = [self.AlbumArt.image = pdt.image, self.AlbumArt.layer.shadowOpacity = 1.0] },
                                  completion: nil)
                
                for i in labels {
                    UILabel.transition(with: i.lbl ?? artist,
                                       duration: duration,
                                       options: .transitionCrossDissolve,
                                       animations: { i.lbl?.text = i.str},
                                       completion: nil)
                }
            }
        }
        
        func setGraphics(_ duration: Double) {
            
            if duration == 0 {
                self.AlbumArt.image = pdt.image
                self.AlbumArt.layer.shadowOpacity = 1.0
                
                for i in labels {
                    i.lbl?.text = i.str
                }
                
            } else {
                DispatchQueue.main.async {
                    //iPad
                    if let artistSong = self.ArtistSong {
                        presentArtistSongAlbumArt(artistSong, duration: duration)
                        //iPhone
                    } else if let artist = self.Artist {
                        presentArtistSongAlbumArt(artist, duration: duration)
                    }
                }
            }
        }
        
        if animated {
            setGraphics(0.5)
        } else if let _ = Artist?.text?.isEmpty {
            setGraphics(0.0)
        } else {
            setGraphics(0.25)
        }
    }
    
    @objc func PlayPause() {
        checkForNetworkError()
        
        PlayerXL.accessibilityHint = ""
        
        if Player.shared.player.rate != 0 || Player.shared.state == .playing {
            DispatchQueue.main.async { [self] in
                updatePlayPauseIcon(play: false)
                Player.shared.new(.paused)
                PlayerXL.accessibilityLabel = "Paused"
                showStatus("Paused")
            }
        } else {
            DispatchQueue.main.async { [self] in
                updatePlayPauseIcon(play: true)
                Player.shared.new(.playing)
                PlayerXL.accessibilityLabel = "Now Playing"
                showStatus("Playing")
            }
        }
    }
    
    func invalidateTimer() {
        self.playerViewTimerX.invalidate()
    }
    
    func startup() {
        startupVolume()
        PulsarAnimation(tune: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if let _  = Artist?.text?.isEmpty {
            Player.shared.syncArt()
        }
        
    #if !targetEnvironment(simulator)
        if !g.demomode && !isMacCatalystApp, let ap2 = ap2volume?.getSoda()  {
            
            VolumeSlider.setValue(ap2, animated: false)
        }
    #endif
        
        title = g.currentChannelName
        startup()
        checkForAllStar()
        isSliderEnabled()
    }
    
    //MARK: Read Write Cache for the PDT (Artist / Song / Album Art)
    @objc func SPXCache() {
        let ps = Player.shared.self
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
    
    func restartPDT() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Timer.scheduledTimer(timeInterval: 3.0, target: self, selector: #selector(self.SPXCache), userInfo: nil, repeats: false)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        shutdownVolume()
        
        UIView.transition(with: self.AlbumArt,
                          duration:0.4,
                          options: .transitionCrossDissolve,
                          animations: { _ = [self.AlbumArt.layer.shadowOpacity = 0.0] },
                          completion: nil)
    }
    
    deinit {
        removeObservers()
    }
    
    //MARK: Speaker Volume with Smooth Frame Animation
    func setSpeakers(value: Float) {
        self.previousSpeaker = self.currentSpeaker
        switch (value) {
        case 0 :
            self.currentSpeaker = .speaker0
        case 0..<0.1 :
            self.currentSpeaker = .speaker1
        case 0.1..<0.2 :
            self.currentSpeaker = .speaker2
        case 0.2..<0.3 :
            self.currentSpeaker = .speaker3
        case 0.3..<0.4 :
            self.currentSpeaker = .speaker4
        case 0.4..<0.5 :
            self.currentSpeaker = .speaker5
        case 0.5..<0.6 :
            self.currentSpeaker = .speaker6
        case 0.6..<0.7 :
            self.currentSpeaker = .speaker7
        case 0.7..<0.8 :
            self.currentSpeaker = .speaker8
        case 0.8..<0.9 :
            self.currentSpeaker = .speaker9
        case 0.9...1.0 :
            self.currentSpeaker = .speaker10
            
        default :
            self.currentSpeaker = .speaker5
        }
        
        if self.previousSpeaker != self.currentSpeaker || value == 0.0 {
            DispatchQueue.main.async {
                let speakerName = self.currentSpeaker.rawValue
                
                UIView.transition(with: self.SpeakerView,
                                  duration:0.2,
                                  options: .transitionCrossDissolve,
                                  animations: { self.SpeakerView.image = UIImage(named: speakerName) },
                                  completion: nil)
                
                self.previousSpeaker = self.currentSpeaker
            }
        }
    }
    
    //MARK: Adjust the volume
    @objc func VolumeChanged(slider: UISlider, event: UIEvent) {
        
        DispatchQueue.main.async {
            let value = slider.value
            self.setSpeakers(value: value)
            
        #if targetEnvironment(simulator)
            Player.shared.player.volume = value
        #else
            // your real device code
            if !self.g.demomode && !self.isMacCatalystApp {
                self.ap2volume?.setSoda(value)
            } else {
                Player.shared.player.volume = value
            }
        #endif
        }
    }
    
    //MARK: Add Volume Slider Action
    func addSliderAction() {
        VolumeSlider.addTarget(self, action: #selector(VolumeChanged(slider:event:)), for: .valueChanged)
        VolumeSlider.isContinuous = true
        if #available(iOS 13.0, *) {
            VolumeSlider.accessibilityRespondsToUserInteraction = true
        }
        VolumeSlider.accessibilityHint = "Volume Slider"
    }
    
    //MARK: Remove Volume Slider Action
    func removeSlider() {
        VolumeSlider.removeTarget(nil, action: #selector(VolumeChanged(slider:event:)), for: .valueChanged)
    }
    func isSliderEnabled() {
        if Player.shared.avSession.currentRoute.outputs.first?.portType == .usbAudio  {
            VolumeSlider.isEnabled = false
        } else {
            VolumeSlider.isEnabled = true
        }
        
    #if !targetEnvironment(simulator)
        if g.demomode || isMacCatalystApp {
            if Player.shared.avSession.currentRoute.outputs.first?.portType == .airPlay  {
                VolumeSlider.isEnabled = false
            } else {
                VolumeSlider.isEnabled = true
            }
        }
     #endif
    }
    
    @objc func handleRouteChange(notification: Notification) {
        airplayRunner()
    }
    
    func airplayRunner() {
        var isTrue = false
        DispatchQueue.main.async { [self] in
            isTrue = tabBarController?.tabBar.selectedItem?.title == channelString
            
            if isTrue && title == g.currentChannelName {
                if Player.shared.avSession.currentRoute.outputs.first?.portType == .airPlay {
                    
                #if !targetEnvironment(simulator)
                    if !g.demomode && !isMacCatalystApp {
                        ap2volume?.setSodaBy(0.0)
                    }
                #endif
                    
                } else {
                #if !targetEnvironment(simulator)
                    if !g.demomode && !isMacCatalystApp {
                        if let vol = ap2volume?.getSoda() {
                            DispatchQueue.main.async {
                                self.VolumeSlider.setValue(vol, animated: true)
                            }
                        }
                    }
                #endif
                }
                
                DispatchQueue.main.async {
                    self.isSliderEnabled()
                }
            }
        }
    }
    
    override func accessibilityPerformMagicTap() -> Bool {
        PlayPause()
        return true
    }
    
    func updatePlayPauseIcon() {
        self.updatePlayPauseIcon(play: Player.shared.player.isBusy)
    }
    
    @objc func willEnterForeground() {
        updatePlayPauseIcon()
        startup()
        
        // Check connection when returning to foreground
        if Player.shared.state == .playing {
            showStatus("Checking connection...")
            Player.shared.checkServerConnection()
        }
    }
    
    func checkForNetworkError() {
        guard net.networkIsConnected else {
            self.displayError(title: "Network error", message: "Check your internet connection and try again", action: "OK")
            return
        }
    }
    
    func displayError(title: String, message: String, action: String) {
        DispatchQueue.main.async {
            self.showAlert(title: title, message: message, action: action)
        }
    }
    
    //Show Alert
    func showAlert(title: String, message:String, action:String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: action, style: .default, handler: { action in
            switch action.style{
            case .default:
                ()
            case .cancel:
                ()
            case .destructive:
                ()
            @unknown default:
                print("error")
            }}))
        self.present(alert, animated: true, completion: nil)
    }
    
    @objc func handleServerConnectionLost() {
        showStatus("Connection lost", duration: 5.0)
    }
    
    @objc func handleServerLaunchFailed() {
        showStatus("Server launch failed", duration: 5.0)
    }
    
    @objc func handlePlayerItemStalled(_ notification: Notification) {
        showStatus("Playback stalled, recovering...", duration: 3.0)
    }
}
