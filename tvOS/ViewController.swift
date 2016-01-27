import UIKit

class ViewController: UIViewController {
    
    let oq = NSOperationQueue()
    
    func newFetchResult(deviceInfo: DeviceInfo, setting: Bool) {
        // FIXME implement
        print("\(deviceInfo): \(setting)") // FIXME remove
    }
    
    func newFetchError(deviceInfo: DeviceInfo, error: AppError) {
        // FIXME handle errors
    }
    
    override func viewDidLoad() {
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
    
//    // MARK: UITableViewDataSource
//    
//    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
//        assert(section == 0)
//        // FIXME implement
//    }
//    
//    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
//        // FIXME implement
//    }
    
}
