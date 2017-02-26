import UIKit
#if !os(tvOS)
    import WatchConnectivity
#endif

class ViewController: UIViewController, ModelViewDelegate, UITableViewDataSource, UITableViewDelegate {
    
    var model: UIModel!
    
    @IBOutlet weak var deviceTable: UITableView!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet var tableFillConstraint: NSLayoutConstraint?
    
    let tableAnimationType = UITableViewRowAnimation.automatic
    let headerFadeTime = TimeInterval(1)
    func row(_ index: Int) -> IndexPath { return IndexPath(row: index, section: 0) }
    var completedWatchToggleTime = TimeInterval()
    
    override func viewDidLoad() {
        model = UIModel(delegate: self)
        
        let nc = NotificationCenter.default
        func applicationDidBecomeActive() { model.start() }
        nc.addObserver(forName: NSNotification.Name.UIApplicationDidBecomeActive, object: nil, queue: nil) { _ in applicationDidBecomeActive() }
        nc.addObserver(forName: NSNotification.Name.UIApplicationWillResignActive, object: nil, queue: nil) { _ in self.model.stop() }
        nc.addObserver(forName: NSNotification.Name.UIApplicationDidEnterBackground, object: nil, queue: nil) { _ in self.model.resetErrors() }
        
        do { // tweak table header presentation:
            func uppercaseAllLabelsInHierarchy(_ view: UIView) {
                if let label = view as? UILabel, let text = label.text {
                    label.text = text.uppercased(with: Locale.current)
                }
                for subview in view.subviews { uppercaseAllLabelsInHierarchy(subview) }
            }
            let header = deviceTable.tableHeaderView!
            uppercaseAllLabelsInHierarchy(header)
            header.alpha = 0
        }
        
        if UIApplication.shared.applicationState == .active {
            // We've missed the first UIApplicationDidBecomeActiveNotification already so just call the function now. This can happen if we're in a navigation controller, for example.
            applicationDidBecomeActive()
        }
        
        #if !os(tvOS)
            if WCSession.isSupported() {
                let session = WCSession.default()
                watchDelegate = WCSD(viewController: self)
                session.delegate = watchDelegate
                session.activate()
            }
        #endif
    }
    
    #if !os(tvOS)
    class WCSD: NSObject, WCSessionDelegate {
        
        init(viewController: ViewController) {
            self.viewController = viewController
        }
        
        let viewController: ViewController
        
        func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
            // Remember that this will be called on a background thread.
            if message.isEmpty { // a request for an update
                viewController.watchRequestedUpdate()
            } else if let deviceInfoData = message[WatchMessageKeys.deviceInfo] { // a request for a toggle
                let deviceInfo = (NSKeyedUnarchiver.unarchiveObject(with: deviceInfoData as! Data) as! DeviceInfoCoding).deviceInfo
                let setting = (message[WatchMessageKeys.setting] as! NSNumber).boolValue
                let toggleRequestTime = (message[WatchMessageKeys.toggleRequestTime] as! NSNumber).doubleValue
                
                OperationQueue.main.addOperation {
                    self.viewController.model.toggleDevice(deviceInfo, toSetting: setting) { self.viewController.completedWatchToggleTime = toggleRequestTime }
                }
            } else {
                assert(false)
            }
        }
        
        // These are implemented to indicate to iOS that we support switching between multiple watches:
        func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
        func sessionDidBecomeInactive(_ session: WCSession) {}
        
        func sessionDidDeactivate(_ session: WCSession) {
            // This is called when changing watches so we need to activate the session again:
            session.activate()
        }
        
    }
    
    var watchDelegate: WCSD?
    
    func watchRequestedUpdate() {
        let task = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        
        OperationQueue.main.addOperation {
            guard UIApplication.shared.applicationState != .active else {
                // We're active and we'll be updating regularly so there's no need to do a special fetch right now.
                self.sendStatusToWatch()
                UIApplication.shared.endBackgroundTask(task)
                return
            }
            
            // We're in the background so we should run a fetch to update the watch.
            self.model.fetchAllStatusesOnce {
                self.sendStatusToWatch()
                UIApplication.shared.endBackgroundTask(task)
            }
        }
    }
    
    func sendStatusToWatch() {
        guard WCSession.isSupported() else { return }
        
        let session = WCSession.default()
        
        guard session.isPaired && session.isWatchAppInstalled && session.activationState == .activated else { return }
        
        var status = [String : AnyObject]()
        if model.deviceCount > 0 {
            let (device, setting) = model.deviceAndSettingAtIndex(0)
            
            status[WatchMessageKeys.deviceInfo] = NSKeyedArchiver.archivedData(withRootObject: DeviceInfoCoding(device)) as AnyObject?
            status[WatchMessageKeys.setting] = setting as AnyObject?
            status[WatchMessageKeys.lastPerformedToggleRequestTime] = completedWatchToggleTime as AnyObject?
        }
        status[WatchMessageKeys.error] = model.hasAnyErrors as AnyObject?
        
        try! session.updateApplicationContext(status)
    }
    #else
    func sendStatusToWatch() {}
    #endif
    
    // MARK: ModelViewDelegate
    
    func insertDeviceViewAtIndex(_ index: Int) {
        deviceTable.insertRows(at: [row(index)], with: tableAnimationType)
        if index == 0 {
            UIView.animate(withDuration: headerFadeTime, animations: { self.deviceTable.tableHeaderView!.alpha = 1 }) 
            sendStatusToWatch()
        }
    }
    
    func reloadDeviceViewAtIndex(_ index: Int) {
        deviceTable.reloadRows(at: [row(index)], with: tableAnimationType)
        if index == 0 { sendStatusToWatch() }
    }
    
    func deleteDeviceViewAtIndex(_ index: Int) {
        deviceTable.deleteRows(at: [row(index)], with: tableAnimationType)
        hideTableHeaderIfNecessary()
        if index == 0 { sendStatusToWatch() }
    }
    
    func deleteDeviceViewsAtIndices(_ indices: [Int]) {
        deviceTable.deleteRows(at: indices.map { row($0) }, with: tableAnimationType)
        hideTableHeaderIfNecessary()
        if indices.contains(0) { sendStatusToWatch() }
    }
    
    func hideTableHeaderIfNecessary() {
        if model.deviceCount == 0 { UIView.animate(withDuration: headerFadeTime, animations: { self.deviceTable.tableHeaderView!.alpha = 0 })  }
    }
    
    func updateErrorText(_ text: String) {
        do {
            let hasError = { self.errorLabel.text != nil && !self.errorLabel.text!.isEmpty }
            let hadError = hasError()
            errorLabel.text = text
            if hadError != hasError() { sendStatusToWatch() }
        }
        
        if let tableFillConstraint = tableFillConstraint {
            let errorLabelShouldBeVisible = !errorLabel.text!.isEmpty
            let errorLabelIsVisible = !tableFillConstraint.isActive
            
            if errorLabelShouldBeVisible != errorLabelIsVisible {
                tableFillConstraint.isActive = !errorLabelShouldBeVisible
            }
        }
    }
    
    // MARK: HIG-compliance housekeeping like that which is done by UITableViewController:
    // https://developer.apple.com/library/tvos/documentation/UserExperience/Conceptual/TableView_iPhone/TableViewAndDataModel/TableViewAndDataModel.html
    override func viewWillAppear(_: Bool) {
        if let selectedRows = deviceTable.indexPathsForSelectedRows {
            for row in selectedRows { deviceTable.deselectRow(at: row, animated: false) }
        }
    }
    override func viewDidAppear(_: Bool) {
        deviceTable.flashScrollIndicators()
    }
    
    #if !os(tvOS)
    @IBAction func deviceSwitchChanged(_ deviceSwitch: UISwitch) {
    toggleDeviceAtIndexPath(deviceTable.indexPathWithSubview(deviceSwitch)!)
    }
    #endif
    
    // MARK: UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        assert(section == 0)
        return model.deviceCount
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        assert(indexPath.section == 0)
        let (device, setting) = model.deviceAndSettingAtIndex(indexPath.row)
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Device", for: indexPath)
        
        #if os(tvOS)
            cell.textLabel!.text = device.description
            cell.detailTextLabel!.text = localString(setting ? "On" : "Off")
        #else
            do {
                let cell = cell as! DeviceTableViewCell
                cell.nameLabel.text = device.description
                cell.settingSwitch.isOn = setting
            }
        #endif
        
        return cell
    }
    
    // MARK: UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        toggleDeviceAtIndexPath(indexPath)
    }
    
    func toggleDeviceAtIndexPath(_ indexPath: IndexPath) {
        assert(indexPath.section == 0)
        model.toggleDeviceAtIndex(indexPath.row)
    }
    
}
