import UIKit

class ViewController: UIViewController, UITableViewDataSource {
    
    @IBOutlet weak var deviceTable: UITableView!
    let oq = NSOperationQueue()
    
    let tableAnimationType = UITableViewRowAnimation.Automatic
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
        }
    }
    
    func newFetchError(deviceInfo: DeviceInfo, error: AppError) {
        // FIXME handle errors
    }
    
    override func viewDidLoad() {
        deviceTable.dataSource = self
        
        let nc = NSNotificationCenter.defaultCenter()
        nc.addObserverForName(UIApplicationDidBecomeActiveNotification, object: nil, queue: nil, usingBlock: applicationDidBecomeActive)
        nc.addObserverForName(UIApplicationWillResignActiveNotification, object: nil, queue: nil, usingBlock: applicationWillResignActive)
    }
    
    func applicationDidBecomeActive(_: NSNotification) {
        oq.addOperation(PeriodicallyFetchAllStatuses(fetchErrorDelegate: newFetchError, fetchResultDelegate: newFetchResult))
    }
    
    func applicationWillResignActive(_: NSNotification) {
        oq.cancelAllOperations()
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
    
}
