import UIKit
#if !os(tvOS)
    import WatchConnectivity
#endif

class ViewController: UIViewController, ModelViewDelegate, UITableViewDataSource, UITableViewDelegate {
    
    let model = Model(self)
    
    @IBOutlet weak var deviceTable: UITableView!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet var tableFillConstraint: NSLayoutConstraint?
    
    let tableAnimationType = UITableViewRowAnimation.Automatic
    let headerFadeTime = NSTimeInterval(1)
    func row(index: Int) -> NSIndexPath { return NSIndexPath(forRow: index, inSection: 0) }
    
    func hideTableHeaderIfNecessary() {
        if model.deviceCount == 0 { UIView.animateWithDuration(headerFadeTime) { self.deviceTable.tableHeaderView!.alpha = 0 } }
    }
    
    override func viewDidLoad() {
        let nc = NSNotificationCenter.defaultCenter()
        func applicationDidBecomeActive() { model.start() }
        nc.addObserverForName(UIApplicationDidBecomeActiveNotification, object: nil, queue: nil) { _ in applicationDidBecomeActive() }
        nc.addObserverForName(UIApplicationWillResignActiveNotification, object: nil, queue: nil) { _ in model.stop() }
        nc.addObserverForName(UIApplicationDidEnterBackgroundNotification, object: nil, queue: nil) { _ in model.resetErrors() }
        
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
                viewController.watchRequestedUpdate()
            } else if let deviceInfoData = message[WatchMessageKeys.deviceInfo] { // a request for a toggle
                let deviceInfo = (NSKeyedUnarchiver.unarchiveObjectWithData(deviceInfoData as! NSData) as! DeviceInfoCoding).deviceInfo
                let setting = (message[WatchMessageKeys.setting] as! NSNumber).boolValue
                let toggleRequestTime = (message[WatchMessageKeys.toggleRequestTime] as! NSNumber).doubleValue
                
                NSOperationQueue.mainQueue().addOperationWithBlock {
                    self.viewController.newFetchResult(deviceInfo, setting: setting) // Update the UI in case we're active or become active soon.
                    self.viewController.toggleDevice(deviceInfo, toSetting: setting, watchToggleRequestTime: toggleRequestTime)
                }
            } else {
                assert(false)
            }
        }
        
    }
    
    var watchDelegate: WCSD?
    
    func watchRequestedUpdate() {
        let task = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler(nil)
        
        NSOperationQueue.mainQueue().addOperationWithBlock {
            guard UIApplication.sharedApplication().applicationState != .Active else {
                // We're active and we'll be updating regularly so there's no need to do a special fetch right now.
                self.sendStatusToWatch()
                UIApplication.sharedApplication().endBackgroundTask(task)
                return
            }
            
            // We're in the background so we should run a fetch to update the watch.
            self.oq.addOperationWithBlock {
                let delegateQueue = NSOperationQueue.mainQueue()
                fetchAllStatusesOnce(delegateQueue: delegateQueue, fetchErrorDelegate: self.newFetchError, fetchResultDelegate: self.newFetchResult)
                delegateQueue.addOperationWithBlock(self.sendStatusToWatch)
                
                UIApplication.sharedApplication().endBackgroundTask(task)
            }
        }
    }
    
    func sendStatusToWatch() {
        guard WCSession.isSupported() else { return }
        
        var status = [String : AnyObject]()
        if let firstDeviceSetting = deviceSettings.first {
            status[WatchMessageKeys.deviceInfo] = NSKeyedArchiver.archivedDataWithRootObject(DeviceInfoCoding(firstDeviceSetting.device))
            status[WatchMessageKeys.setting] = firstDeviceSetting.setting
            status[WatchMessageKeys.lastPerformedToggleRequestTime] = completedWatchToggleTime
        }
        status[WatchMessageKeys.error] = !errors.isEmpty || weHaventSeenADeviceInAWhile()
        
        try! WCSession.defaultSession().updateApplicationContext(status)
    }
    #endif
    
    // MARK: ModelViewDelegate
    
    // FIXME reorder these methods:
    func reloadDeviceViewAtIndex(index: Int) {
        deviceTable.reloadRowsAtIndexPaths([row(index)], withRowAnimation: tableAnimationType)
        if index == 0 { sendStatusToWatch() }
    }
    
    func insertDeviceViewAtIndex(index: Int) {
        deviceTable.insertRowsAtIndexPaths([row(index)], withRowAnimation: tableAnimationType)
        if index == 0 {
            UIView.animateWithDuration(headerFadeTime) { self.deviceTable.tableHeaderView!.alpha = 1 }
            sendStatusToWatch()
        }
    }
    
    func deleteDeviceViewAtIndex(index: Int) {
        deviceTable.deleteRowsAtIndexPaths([row(index)], withRowAnimation: tableAnimationType)
        hideTableHeaderIfNecessary()
        if index == 0 { sendStatusToWatch() }
    }
    
    func updateErrorText(text: String) {
        do {
            let hasError = { self.errorLabel.text != nil && !self.errorLabel.text!.isEmpty }
            let hadError = hasError()
            errorLabel.text = text
            if hadError != hasError() { sendStatusToWatch() }
        }
        
        if let tableFillConstraint = tableFillConstraint {
            let errorLabelShouldBeVisible = !errorLabel.text!.isEmpty
            let errorLabelIsVisible = !tableFillConstraint.active
            
            if errorLabelShouldBeVisible != errorLabelIsVisible {
                tableFillConstraint.active = !errorLabelShouldBeVisible
            }
        }
    }
    
    func deleteDeviceViewsAtIndices(indices: [Int]) {
        deviceTable.deleteRowsAtIndexPaths(indices.map { row($0) }, withRowAnimation: tableAnimationType)
        hideTableHeaderIfNecessary()
        if indices.contains(0) { sendStatusToWatch() }
    }
    
    // MARK: HIG-compliance housekeeping like that which is done by UITableViewController:
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
        return model.deviceCount
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
        if deviceSettingsIndex == 0 { sendStatusToWatch() }
        
        toggleDevice(newDeviceSetting.device, toSetting: newDeviceSetting.setting)
    }
    
    func toggleDevice(deviceInfo: DeviceInfo, toSetting wantedSetting: Bool, watchToggleRequestTime: NSTimeInterval? = nil) {
        // It's useful for the user if we clear out any errors from previous attempts now, because we're about to try again. If the old error just stayed on screen and was replaced by the same error then it would be harder to tell what had happened.
        removeErrorFor(deviceInfo, forOperation: .Toggle)
        updateErrorText()
        
        ++toggleOperationsOutstanding[deviceInfo]
        
        oq.addOperationWithBlock {
            let delegateQueue = NSOperationQueue.mainQueue()
            
            do {
                try setSetting(deviceInfo, setting: wantedSetting)
            } catch let e as AppError {
                delegateQueue.addOperationWithBlock {
                    --self.toggleOperationsOutstanding[deviceInfo]
                    self.completedWatchToggleTime = watchToggleRequestTime ?? self.completedWatchToggleTime
                    self.newOperationError(deviceInfo, error: e, operation: .Toggle)
                }
                return
            } catch { assert(false) }
            
            guard let newSetting: Bool = {
                do {
                    let newSetting = try fetchSetting(deviceInfo)
                    delegateQueue.addOperationWithBlock {
                        --self.toggleOperationsOutstanding[deviceInfo]
                        self.completedWatchToggleTime = watchToggleRequestTime ?? self.completedWatchToggleTime
                        self.newFetchResult(deviceInfo, setting: newSetting)
                    }
                    return newSetting
                } catch let e as AppError {
                    delegateQueue.addOperationWithBlock {
                        --self.toggleOperationsOutstanding[deviceInfo]
                        self.completedWatchToggleTime = watchToggleRequestTime ?? self.completedWatchToggleTime
                        self.newFetchError(deviceInfo, error: e)
                    }
                } catch { assert(false) }
                return nil
                }() else { return }
            
            if newSetting != wantedSetting {
                delegateQueue.addOperationWithBlock { self.newOperationError(deviceInfo, error: AppError(kind: .SettingDidNotChange), operation: .Toggle) }
            }
        }
    }
    
}
