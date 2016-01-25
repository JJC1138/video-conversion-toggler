import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    let oq = NSOperationQueue()
    
    func applicationDidBecomeActive(application: UIApplication) {
        oq.addOperation(PeriodicallyFetchAllStatuses())
    }
    
    func applicationWillResignActive(application: UIApplication) {
        oq.cancelAllOperations()
    }
    
}
