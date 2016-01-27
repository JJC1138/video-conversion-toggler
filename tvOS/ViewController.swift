import UIKit

class ViewController: UIViewController {
    
    let oq = NSOperationQueue()
    
    class PeriodicallyFetchAllStatuses: NSOperation {
        
        override func main() {
            let fetchQueue = NSOperationQueue()
            while (!cancelled) {
                discoverCompatibleDevices { deviceInfo in fetchQueue.addOperation(NSBlockOperation() {
                    do {
                        let setting = try fetchSetting(deviceInfo)
                        // FIXME handle results
                        print("\(deviceInfo): \(setting)") // FIXME remove
                    } catch let e as AppError {
                        // FIXME handle errors
                    } catch {}
                    })
                }
            }
            fetchQueue.waitUntilAllOperationsAreFinished()
        }
        
    }
    
    override func viewDidLoad() {
        let nc = NSNotificationCenter.defaultCenter()
        nc.addObserverForName(UIApplicationDidBecomeActiveNotification, object: nil, queue: nil, usingBlock: applicationDidBecomeActive)
        nc.addObserverForName(UIApplicationWillResignActiveNotification, object: nil, queue: nil, usingBlock: applicationWillResignActive)
    }
    
    func applicationDidBecomeActive(_: NSNotification) {
        oq.addOperation(PeriodicallyFetchAllStatuses())
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
