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
        
        WCSession.defaultSession().sendMessage(status, replyHandler: nil, errorHandler: sendMessageDidCauseError)
    }
    
    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
        deviceErrorLabel.setHidden(!Bool(applicationContext[WatchMessageKeys.error] as! NSNumber))
        
        if let deviceInfoData = applicationContext[WatchMessageKeys.deviceInfo] {
            let deviceInfo = (NSKeyedUnarchiver.unarchiveObjectWithData(deviceInfoData as! NSData) as! DeviceInfoCoding).deviceInfo
            let setting = Bool(applicationContext[WatchMessageKeys.setting] as! NSNumber)
            
            self.deviceInfo = deviceInfo
            
            deviceInfoGroup.setHidden(false)
            deviceNameLabel.setText(deviceInfo.name)
            deviceSettingSwitch.setOn(setting)
        } else {
            deviceInfoGroup.setHidden(true)
        }
    }
    
}
