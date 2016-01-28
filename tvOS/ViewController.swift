import UIKit

class ViewController: UIViewController, UITableViewDataSource {
    
    @IBOutlet weak var deviceTable: UITableView!
    let oq = NSOperationQueue()
    var removeOldResultsAndErrorsTimer: NSTimer?
    
    let tableAnimationType = UITableViewRowAnimation.Automatic
    let headerFadeTime = NSTimeInterval(1)
    func row(index: Int) -> NSIndexPath { return NSIndexPath(forRow: index, inSection: 0) }
    
    struct DeviceSetting {
        let device: DeviceInfo
        let setting: Bool
        let retrieved: NSTimeInterval
    }
    
    // Only touch these from the main thread:
    var deviceSettings = [DeviceSetting]()
    
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
    }
    
    func newFetchError(deviceInfo: DeviceInfo, error: AppError) {
        // FIXME handle errors
    }
    
    func removeOldResultsAndErrors() {
        let now = awakeUptime()
        let oldestAllowedResultTime = now - 5
        
        func isCurrent(setting: DeviceSetting) -> Bool { return setting.retrieved >= oldestAllowedResultTime }
        
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
        if deviceSettings.count == 0 { UIView.animateWithDuration(headerFadeTime) { self.deviceTable.tableHeaderView!.alpha = 0 } }
        
        // FIXME remove old errors (and don't early exit from the all(isCurrent) check above)
    }
    
    override func viewDidLoad() {
        deviceTable.dataSource = self
        
        let nc = NSNotificationCenter.defaultCenter()
        nc.addObserverForName(UIApplicationDidBecomeActiveNotification, object: nil, queue: nil) { _ in
            self.oq.addOperation(PeriodicallyFetchAllStatuses(fetchErrorDelegate: self.newFetchError, fetchResultDelegate: self.newFetchResult))
            self.removeOldResultsAndErrorsTimer = {
                // FUTURETODO Use the non-string selector initialization syntax when SE-0022 is implemented:
                let t = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: "removeOldResultsAndErrors", userInfo: nil, repeats: true)
                t.tolerance = 3
                return t
            }()
        }
        nc.addObserverForName(UIApplicationWillResignActiveNotification, object: nil, queue: nil) { _ in
            self.oq.cancelAllOperations()
            if let removeOldResultsAndErrorsTimer = self.removeOldResultsAndErrorsTimer { removeOldResultsAndErrorsTimer.invalidate() }
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
