import UIKit
#if !os(tvOS)
    import WatchConnectivity
#endif

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    @IBOutlet weak var deviceTable: UITableView!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet var tableFillConstraint: NSLayoutConstraint?
    let oq = NSOperationQueue()
    var removeOldResultsTimer: NSTimer?
    
    let tableAnimationType = UITableViewRowAnimation.Automatic
    let headerFadeTime = NSTimeInterval(1)
    func row(index: Int) -> NSIndexPath { return NSIndexPath(forRow: index, inSection: 0) }
    
    struct DeviceSetting {
        let device: DeviceInfo
        let setting: Bool
        let retrieved: NSTimeInterval
    }
    
    enum Operation {
        case FetchSetting
        case Toggle
    }
    
    struct Error {
        let device: DeviceInfo
        let error: AppError
        let cause: Operation
    }
    
    // Only touch these from the main thread:
    var deviceSettings = [DeviceSetting]()
    var errors = [Error]()
    var lastTimeADeviceWasSeen = NSTimeInterval()
    
    func newFetchResult(deviceInfo: DeviceInfo, setting: Bool) {
        lastTimeADeviceWasSeen = awakeUptime()
        let newSetting = DeviceSetting(device: deviceInfo, setting: setting, retrieved: awakeUptime())
        
        if let index = (deviceSettings.indexOf { $0.device == deviceInfo }) {
            // We already have an entry for this device.
            let oldSetting = deviceSettings[index].setting
            deviceSettings[index] = newSetting // Update at least the retrieval time whether the setting has changed or not.
            if oldSetting != setting {
                deviceTable.reloadRowsAtIndexPaths([row(index)], withRowAnimation: tableAnimationType)
            }
        } else {
            deviceSettings.append(newSetting)
            deviceTable.insertRowsAtIndexPaths([row(deviceSettings.count - 1)], withRowAnimation: tableAnimationType)
            if deviceSettings.count == 1 { UIView.animateWithDuration(headerFadeTime) { self.deviceTable.tableHeaderView!.alpha = 1 } }
        }
        
        removeErrorFor(deviceInfo, forOperation: .FetchSetting)
        updateErrorText()
    }
    
    func removeErrorFor(device: DeviceInfo, forOperation operation: Operation) {
        if let i = errors.indexOf({ $0.device == device && $0.cause == operation }) {
            // We previously had an error with this device when performing this operation, but it has succeeded now so whatever was causing the error is presumably now fixed.
            errors.removeAtIndex(i)
        }
    }
    
    func newFetchError(deviceInfo: DeviceInfo, error: AppError) {
        newOperationError(deviceInfo, error: error, operation: .FetchSetting)
        
        // We haven't fetched the setting successfully and any previous setting we fetched might be out of date so remove it to avoid confusing users with possibly incorrect information:
        removeSettingFor(deviceInfo)
    }
    
    func newOperationError(deviceInfo: DeviceInfo, error: AppError, operation: Operation) {
        lastTimeADeviceWasSeen = awakeUptime()
        let newError = Error(device: deviceInfo, error: error, cause: operation)
        
        if let index = (errors.indexOf { $0.device == deviceInfo }) {
            // We already have an error for this device.
            errors[index] = newError
        } else {
            errors.append(newError)
        }
        updateErrorText()
    }
    
    func updateErrorText() {
        errorLabel.text = {
            if self.errors.count > 0 {
                return (self.errors.map { describeError($0.error, forDevice: $0.device) }).joinWithSeparator("\n\n") + "\n\n\(errorContactInstruction())"
            } else {
                if weHaventSeenADeviceInAWhile() {
                    return noDevicesContactInstruction()
                } else {
                    return ""
                }
            }
            }()
        
        if let tableFillConstraint = tableFillConstraint {
            let errorLabelShouldBeVisible = !errorLabel.text!.isEmpty
            let errorLabelIsVisible = !tableFillConstraint.active
            
            if errorLabelShouldBeVisible != errorLabelIsVisible {
                tableFillConstraint.active = !errorLabelShouldBeVisible
            }
        }
    }
    
    func weHaventSeenADeviceInAWhile() -> Bool {
        return deviceSettings.isEmpty && errors.isEmpty && (awakeUptime() - lastTimeADeviceWasSeen) >= 5
    }
    
    func removeSettingFor(device: DeviceInfo) {
        if let i = deviceSettings.indexOf( { $0.device == device } ) {
            deviceSettings.removeAtIndex(i)
            deviceTable.deleteRowsAtIndexPaths([row(i)], withRowAnimation: tableAnimationType)
            hideTableHeaderIfNecessary()
        }
    }
    
    func removeOldResults() {
        let now = awakeUptime()
        let oldestAllowedTime = now - 5
        
        func isCurrent(setting: DeviceSetting) -> Bool { return setting.retrieved >= oldestAllowedTime }
        
        if !deviceSettings.all(isCurrent) {
            var newSettings = [DeviceSetting]()
            var rowsToDelete = [NSIndexPath]()
            for (index, setting) in deviceSettings.enumerate() {
                if isCurrent(setting) {
                    newSettings.append(setting)
                } else {
                    rowsToDelete.append(row(index))
                }
            }
            
            assert(rowsToDelete.count > 0)
            
            deviceSettings = newSettings
            deviceTable.deleteRowsAtIndexPaths(rowsToDelete, withRowAnimation: tableAnimationType)
            hideTableHeaderIfNecessary()
        }
        
        if weHaventSeenADeviceInAWhile() { updateErrorText() }
    }
    
    func hideTableHeaderIfNecessary() {
        if deviceSettings.count == 0 { UIView.animateWithDuration(headerFadeTime) { self.deviceTable.tableHeaderView!.alpha = 0 } }
    }
    
    override func viewDidLoad() {
        let nc = NSNotificationCenter.defaultCenter()
        func applicationDidBecomeActive() {
            lastTimeADeviceWasSeen = awakeUptime()
            oq.addOperation(PeriodicallyFetchAllStatuses(fetchErrorDelegate: { di, e in self.newOperationError(di, error: e, operation: .FetchSetting) } , fetchResultDelegate: self.newFetchResult))
            removeOldResultsTimer = {
                // FUTURETODO Use the non-string selector initialization syntax when SE-0022 is implemented:
                let t = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: "removeOldResults", userInfo: nil, repeats: true)
                t.tolerance = 3
                return t
                }()
        }
        nc.addObserverForName(UIApplicationDidBecomeActiveNotification, object: nil, queue: nil) { _ in applicationDidBecomeActive() }
        nc.addObserverForName(UIApplicationWillResignActiveNotification, object: nil, queue: nil) { _ in
            self.oq.cancelAllOperations()
            if let removeOldResultsTimer = self.removeOldResultsTimer { removeOldResultsTimer.invalidate() }
        }
        nc.addObserverForName(UIApplicationDidEnterBackgroundNotification, object: nil, queue: nil) { _ in
            self.errors = []
            self.lastTimeADeviceWasSeen = awakeUptime()
            self.updateErrorText()
        }
        
        do { // tweak table header presentation:
            func uppercaseAllLabelsInHierarchy(view: UIView) {
                if let label = view as? UILabel, text = label.text {
                    label.text = text.uppercaseStringWithLocale(NSLocale.currentLocale())
                }
                for subview in view.subviews { uppercaseAllLabelsInHierarchy(subview) }
            }
            let header = deviceTable.tableHeaderView!
            uppercaseAllLabelsInHierarchy(header)
            header.alpha = 0
        }
        
        if UIApplication.sharedApplication().applicationState == .Active {
            // We've missed the first UIApplicationDidBecomeActiveNotification already so just call the function now. This can happen if we're in a navigation controller, for example.
            applicationDidBecomeActive()
        }
        
        #if !os(tvOS)
            if WCSession.isSupported() {
                let session = WCSession.defaultSession()
                watchDelegate = WCSD(viewController: self)
                session.delegate = watchDelegate
                session.activateSession()
                print("activated session on phone") // FIXME remove
            }
        #endif
    }
    
    #if !os(tvOS)
    class WCSD: NSObject, WCSessionDelegate {
        
        init(viewController: ViewController) {
            self.viewController = viewController
        }
        
        let viewController: ViewController
        
        func session(session: WCSession, didReceiveMessage message: [String: AnyObject]) {
            // Remember that this will be called on a background thread.
            if message.isEmpty { // a request for an update
                NSOperationQueue.mainQueue().addOperationWithBlock(self.viewController.watchRequestedUpdate)
            }
            session.sendMessage(["msg": "received message on phone in state \(UIApplication.sharedApplication().applicationState == .Active ? "active" : "not active")"], replyHandler: nil, errorHandler: { print($0) }) // FIXME remove
        }
        
    }
    
    var watchDelegate: WCSD?
    
    func watchRequestedUpdate() {
        guard UIApplication.sharedApplication().applicationState != .Active else {
            // We're active so we'll be updating the watch regularly when we get data so there's no need to do anything special now.
            WCSession.defaultSession().sendMessage(["msg": "skipping update because phone app is active"], replyHandler: nil, errorHandler: nil) // FIXME remove
            return
        }
        
        // We're in the background so we should run a fetch to update the watch.
        oq.addOperationWithBlock {
            let delegateQueue = NSOperationQueue.mainQueue()
            let fetchQueue = NSOperationQueue()
            discoverCompatibleDevices { deviceInfo in fetchQueue.addOperationWithBlock {
                do {
                    let setting = try fetchSetting(deviceInfo)
                    delegateQueue.addOperationWithBlock { self.newFetchResult(deviceInfo, setting: setting) }
                } catch let e as AppError {
                    delegateQueue.addOperationWithBlock { self.newFetchError(deviceInfo, error: e) }
                } catch { assert(false) }
                }
            }
            fetchQueue.waitUntilAllOperationsAreFinished()
            WCSession.defaultSession().sendMessage(["msg": "did an update on behalf of watch"], replyHandler: nil, errorHandler: nil) // FIXME remove
            delegateQueue.addOperationWithBlock(self.sendStatusToWatch)
        }
    }
    
    func sendStatusToWatch() {
        guard WCSession.isSupported() else { return }
        
        var status = [String : AnyObject]()
        if let firstDeviceSetting = deviceSettings.first {
            status[WatchMessageKeys.deviceInfo] = NSKeyedArchiver.archivedDataWithRootObject(DeviceInfoCoding(firstDeviceSetting.device))
            status[WatchMessageKeys.setting] = firstDeviceSetting.setting
        }
        status[WatchMessageKeys.error] = !errors.isEmpty || weHaventSeenADeviceInAWhile()
        
        try! WCSession.defaultSession().updateApplicationContext(status)
    }
    #endif
    
    // HIG-compliance housekeeping like that which is done by UITableViewController:
    // https://developer.apple.com/library/tvos/documentation/UserExperience/Conceptual/TableView_iPhone/TableViewAndDataModel/TableViewAndDataModel.html
    override func viewWillAppear(_: Bool) {
        if let selectedRows = deviceTable.indexPathsForSelectedRows {
            for row in selectedRows { deviceTable.deselectRowAtIndexPath(row, animated: false) }
        }
    }
    override func viewDidAppear(_: Bool) {
        deviceTable.flashScrollIndicators()
    }
    
    #if !os(tvOS)
    @IBAction func deviceSwitchChanged(deviceSwitch: UISwitch) {
    toggleDeviceAtIndexPath(deviceTable.indexPathWithSubview(deviceSwitch)!)
    }
    #endif
    
    // MARK: UITableViewDataSource
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        assert(section == 0)
        return deviceSettings.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        assert(indexPath.section == 0)
        let deviceSetting = deviceSettings[indexPath.row]
        
        let cell = tableView.dequeueReusableCellWithIdentifier("Device", forIndexPath: indexPath)
        
        #if os(tvOS)
            cell.textLabel!.text = deviceSetting.device.description
            cell.detailTextLabel!.text = localString(deviceSetting.setting ? "On" : "Off")
        #else
            do {
                let cell = cell as! DeviceTableViewCell
                cell.nameLabel.text = deviceSetting.device.description
                cell.settingSwitch.on = deviceSetting.setting
            }
        #endif
        
        return cell
    }
    
    // MARK: UITableViewDelegate
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        toggleDeviceAtIndexPath(indexPath)
    }
    
    func toggleDeviceAtIndexPath(indexPath: NSIndexPath) {
        assert(indexPath.section == 0)
        let deviceSettingsIndex = indexPath.row
        let selectedDeviceSetting = self.deviceSettings[deviceSettingsIndex]
        
        let newDeviceSetting = DeviceSetting(device: selectedDeviceSetting.device, setting: !selectedDeviceSetting.setting, retrieved: awakeUptime())
        self.deviceSettings[deviceSettingsIndex] = newDeviceSetting
        self.deviceTable.reloadRowsAtIndexPaths([indexPath], withRowAnimation: self.tableAnimationType)
        
        // It's useful for the user if we clear out any errors from previous attempts now, because we're about to try again. If the old error just stayed on screen and was replaced by the same error then it would be harder to tell what had happened.
        removeErrorFor(selectedDeviceSetting.device, forOperation: .Toggle)
        updateErrorText()
        
        oq.addOperationWithBlock {
            let deviceInfo = selectedDeviceSetting.device
            let wantedSetting = !selectedDeviceSetting.setting
            let delegateQueue = NSOperationQueue.mainQueue()
            
            do {
                try setSetting(deviceInfo, setting: wantedSetting)
            } catch let e as AppError {
                delegateQueue.addOperationWithBlock { self.newOperationError(deviceInfo, error: e, operation: .Toggle) }
                return
            } catch { assert(false) }
            
            guard let newSetting: Bool = {
                do {
                    let newSetting = try fetchSetting(deviceInfo)
                    delegateQueue.addOperationWithBlock { self.newFetchResult(deviceInfo, setting: newSetting) }
                    return newSetting
                } catch let e as AppError {
                    delegateQueue.addOperationWithBlock { self.newFetchError(deviceInfo, error: e) }
                } catch { assert(false) }
                return nil
                }() else { return }
            
            if newSetting != wantedSetting {
                delegateQueue.addOperationWithBlock { self.newOperationError(deviceInfo, error: AppError(kind: .SettingDidNotChange), operation: .Toggle) }
            }
        }
    }
    
}
