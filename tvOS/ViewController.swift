import UIKit

class ViewController: UIViewController, UITableViewDataSource {
    
    @IBOutlet weak var deviceTable: UITableView!
    @IBOutlet weak var errorLabel: UILabel!
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
    
    func newFetchResult(deviceInfo: DeviceInfo, setting: Bool) {
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
    }
    
    func removeErrorFor(device: DeviceInfo, forOperation operation: Operation) {
        if let i = errors.indexOf({ $0.device == device && $0.cause == operation }) {
            // We previously had an error with this device when performing this operation, but it has succeeded now so whatever was causing the error is presumably now fixed.
            errors.removeAtIndex(i)
            updateErrorText()
        }
    }
    
    func newFetchError(deviceInfo: DeviceInfo, error: AppError) {
        let newError = Error(device: deviceInfo, error: error, cause: .FetchSetting)
        
        if let index = (errors.indexOf { $0.device == deviceInfo }) {
            // We already have an error for this device.
            errors[index] = newError
        } else {
            errors.append(newError)
        }
        updateErrorText()
        
        // We haven't fetched the setting successfully and any previous setting we fetched might be out of date so remove it to avoid confusing users with possibly incorrect information:
        removeSettingFor(deviceInfo)
    }
    
    func updateErrorText() {
        errorLabel.text = {
            if self.errors.count > 0 {
                return (self.errors.map { describeError($0.error, forDevice: $0.device) }).joinWithSeparator("\n\n") + "\n\n\(errorContactInstruction())"
            } else {
                return ""
            }
            }()
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
        
        if deviceSettings.all(isCurrent) { return }
        
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
    }
    
    func hideTableHeaderIfNecessary() {
        if deviceSettings.count == 0 { UIView.animateWithDuration(headerFadeTime) { self.deviceTable.tableHeaderView!.alpha = 0 } }
    }
    
    override func viewDidLoad() {
        deviceTable.dataSource = self
        
        let nc = NSNotificationCenter.defaultCenter()
        nc.addObserverForName(UIApplicationDidBecomeActiveNotification, object: nil, queue: nil) { _ in
            self.oq.addOperation(PeriodicallyFetchAllStatuses(fetchErrorDelegate: self.newFetchError, fetchResultDelegate: self.newFetchResult))
            self.removeOldResultsTimer = {
                // FUTURETODO Use the non-string selector initialization syntax when SE-0022 is implemented:
                let t = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: "removeOldResults", userInfo: nil, repeats: true)
                t.tolerance = 3
                return t
            }()
        }
        nc.addObserverForName(UIApplicationWillResignActiveNotification, object: nil, queue: nil) { _ in
            self.oq.cancelAllOperations()
            if let removeOldResultsTimer = self.removeOldResultsTimer { removeOldResultsTimer.invalidate() }
        }
        nc.addObserverForName(UIApplicationDidEnterBackgroundNotification, object: nil, queue: nil) { _ in
            self.errors = []
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
    }
    
    // MARK: UITableViewDataSource
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        assert(section == 0)
        return deviceSettings.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        assert(indexPath.section == 0)
        let deviceSetting = deviceSettings[indexPath.row]
        
        let cell = tableView.dequeueReusableCellWithIdentifier("Device", forIndexPath: indexPath)
        cell.textLabel!.text = deviceSetting.device.description
        cell.detailTextLabel!.text = localString(deviceSetting.setting ? "On" : "Off")
        return cell
    }

    // HIG-compliance housekeeping that would be done by UITableViewController:
    // https://developer.apple.com/library/tvos/documentation/UserExperience/Conceptual/TableView_iPhone/TableViewAndDataModel/TableViewAndDataModel.html
    override func viewWillAppear(_: Bool) {
        if let selectedRows = deviceTable.indexPathsForSelectedRows {
            for row in selectedRows { deviceTable.deselectRowAtIndexPath(row, animated: false) }
        }
    }
    override func viewDidAppear(_: Bool) {
        deviceTable.flashScrollIndicators()
    }
    
}
