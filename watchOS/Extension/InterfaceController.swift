import WatchConnectivity
import WatchKit

class InterfaceController: WKInterfaceController, WCSessionDelegate {
    
    @IBOutlet var deviceInfoGroup: WKInterfaceGroup!
    @IBOutlet var deviceNameLabel: WKInterfaceLabel!
    @IBOutlet var deviceSettingSwitch: WKInterfaceSwitch!
    @IBOutlet var deviceErrorLabel: WKInterfaceLabel!
    @IBOutlet var phoneUnreachableErrorLabel: WKInterfaceLabel!
    
    var deviceInfo: DeviceInfo?
    
    override func willActivate() {
        super.willActivate()
        
        print("WKInterfaceController.willActivate()") // FIXME remove
        
        let session = WCSession.defaultSession()
        session.delegate = self
        session.activateSession()
        print("activated session on watch") // FIXME remove
        // FUTURETODO in watchOS 2.2 WCSession.activateSession() completes asynchronously so we can't count on it be activated already here:
        sessionReachabilityDidChange(session)
    }
    
    func sessionReachabilityDidChange(session: WCSession) {
        print("on watch session is now \(session.reachable ? "reachable" : "unreachable")") // FIXME remove
        if session.reachable {
            session.sendMessage([:], replyHandler: nil, errorHandler: sendMessageDidCauseError) // request an update
        } else {
            deviceInfo = nil
            
            phoneUnreachableErrorLabel.setHidden(false)
            deviceInfoGroup.setHidden(true)
            deviceErrorLabel.setHidden(true)
        }
    }
    
    func sendMessageDidCauseError(error: NSError) {
        #if DEBUG
            print(error)
        #endif
    }
    
    @IBAction func switchToggled(value: Bool) {
        WCSession.defaultSession().sendMessage(["Hi": value], replyHandler: nil, errorHandler: sendMessageDidCauseError) // FIXME implement properly
    }
    
    func session(session: WCSession, didReceiveMessage message: [String : AnyObject]) {
        // Remember that this will be called on a background thread.
        print("received message on watch: \(message)") // FIXME remove
    }
    
    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
        print("received application context on watch: \(applicationContext)") // FIXME remove
        
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
