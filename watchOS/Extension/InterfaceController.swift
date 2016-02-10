import WatchConnectivity
import WatchKit

class InterfaceController: WKInterfaceController, WCSessionDelegate {
    
    @IBOutlet var deviceInfoGroup: WKInterfaceGroup!
    @IBOutlet var deviceNameLabel: WKInterfaceLabel!
    @IBOutlet var deviceSettingSwitch: WKInterfaceSwitch!
    @IBOutlet var deviceErrorLabel: WKInterfaceLabel!
    @IBOutlet var phoneUnreachableErrorLabel: WKInterfaceLabel!
    
    var deviceInfo: DeviceInfo?
    var requestUpdateTimer: NSTimer?
    var lastToggleRequestTime = NSTimeInterval()
    
    override func willActivate() {
        super.willActivate()
        
        let session = WCSession.defaultSession()
        session.delegate = self
        session.activateSession()
        // FUTURETODO in watchOS 2.2 WCSession.activateSession() completes asynchronously so we can't count on it be activated already here:
        sessionReachabilityDidChange(session)
        
        requestUpdateTimer = {
            // FUTURETODO Use the non-string selector initialization syntax when SE-0022 is implemented:
            let t = NSTimer.scheduledTimerWithTimeInterval(3, target: self, selector: "requestAnUpdate", userInfo: nil, repeats: true)
            t.tolerance = 1
            return t
            }()
    }
    
    override func didDeactivate() {
        super.didDeactivate()
        
        requestUpdateTimer?.invalidate()
    }
    
    func sessionReachabilityDidChange(session: WCSession) {
        if session.reachable {
            requestAnUpdate()
            phoneUnreachableErrorLabel.setHidden(true)
        } else {
            deviceInfo = nil
            
            phoneUnreachableErrorLabel.setHidden(false)
            deviceInfoGroup.setHidden(true)
            deviceErrorLabel.setHidden(true)
        }
    }
    
    func requestAnUpdate() {
        let session = WCSession.defaultSession()
        guard session.reachable else { return }
        session.sendMessage([:], replyHandler: nil, errorHandler: sendMessageDidCauseError)
    }
    
    func sendMessageDidCauseError(error: NSError) {
        #if DEBUG
            print(error)
        #endif
    }
    
    @IBAction func switchToggled(value: Bool) {
        guard let deviceInfo = deviceInfo else { return }
        
        var status = [String : AnyObject]()
        status[WatchMessageKeys.deviceInfo] = NSKeyedArchiver.archivedDataWithRootObject(DeviceInfoCoding(deviceInfo))
        status[WatchMessageKeys.setting] = value
        lastToggleRequestTime = awakeUptime()
        status[WatchMessageKeys.toggleRequestTime] = lastToggleRequestTime
        
        WCSession.defaultSession().sendMessage(status, replyHandler: nil, errorHandler: sendMessageDidCauseError)
    }
    
    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
        NSOperationQueue.mainQueue().addOperationWithBlock {
            self.deviceErrorLabel.setHidden(!(applicationContext[WatchMessageKeys.error] as! NSNumber).boolValue)
            
            if let deviceInfoData = applicationContext[WatchMessageKeys.deviceInfo] {
                do {
                    let timeSinceLastToggleRequest = awakeUptime() - self.lastToggleRequestTime
                    // When we've just made a toggle request we might receive context updates that were sent before our toggle request completed. Those could make the switch flick back to its old value, before switching again to the right value when a context update comes in after the toggle has taken effect. That's annoying and so we want to ignore those old context updates. The way we do that is to send the phone our timestamp when we request a toggle and the phone echoes that back to us in the context updates only after that toggle has completed.
                    // There are some awkward edge cases with that logic, though, because the phone app might restart and thus forget the toggle timestamp we gave it, or the watch might reboot and change the uptime basis of our timestamps. To work around those we only apply this ignoring logic for a short time after making a toggle request. After that time has elapsed we accept context updates unconditionally and that drastically limits the amount of time that the edge cases could cause problems.
                    if timeSinceLastToggleRequest < 5 {
                        let lastPerformedToggleRequestTime = (applicationContext[WatchMessageKeys.lastPerformedToggleRequestTime] as! NSNumber).doubleValue
                        
                        if lastPerformedToggleRequestTime < self.lastToggleRequestTime {
                            // ignoring context update shortly after toggle request because it was from before the request
                            return
                        } else {
                            // accepting context update shortly after toggle request because its timestamp matches the request
                        }
                    }
                }
                
                let deviceInfo = (NSKeyedUnarchiver.unarchiveObjectWithData(deviceInfoData as! NSData) as! DeviceInfoCoding).deviceInfo
                let setting = (applicationContext[WatchMessageKeys.setting] as! NSNumber).boolValue
                
                self.deviceInfo = deviceInfo
                
                self.deviceInfoGroup.setHidden(false)
                self.deviceNameLabel.setText(deviceInfo.name)
                self.deviceSettingSwitch.setOn(setting)
            } else {
                self.deviceInfoGroup.setHidden(true)
            }
        }
    }
    
}
