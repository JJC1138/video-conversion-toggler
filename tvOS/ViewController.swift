import UIKit

class ViewController: UIViewController, UITableViewDataSource {
    
    @IBOutlet weak var deviceTable: UITableView!
    let oq = NSOperationQueue()
    
    struct DeviceSetting {
        let device: DeviceInfo
        let setting: Bool
    }
    
    var deviceSettings = [DeviceSetting]()
    
    func newFetchResult(deviceInfo: DeviceInfo, setting: Bool) {
        // FIXME replace existing entry for this device if present
        deviceSettings.append(DeviceSetting(device: deviceInfo, setting: setting))
        // FIXME handle this more precisely:
        deviceTable.reloadData()
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
        oq.addOperation(PeriodicallyFetchAllStatuses(fetchResultDelegate: newFetchResult, fetchErrorDelegate: newFetchError))
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
