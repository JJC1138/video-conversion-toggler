import UIKit

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        let mainOperationQueue = NSOperationQueue()
        
        mainOperationQueue.addOperation(NSBlockOperation {
            discoverCompatibleDevices { deviceInfo in
                mainOperationQueue.addOperation(NSBlockOperation {
                    toggleSetting(deviceInfo)
                    })
            }
            })
        
        let finishingStepsQueue = NSOperationQueue()
        
        finishingStepsQueue.addOperation(NSBlockOperation {
            mainOperationQueue.waitUntilAllOperationsAreFinished()
            
            for deviceInfo in deviceSettings.keys() {
                guard let setting = deviceSettings[deviceInfo] else { continue }
                
                print("\(deviceInfo): \(localString(setting ? "on" : "off"))")
            }
            
            var anyErrors = false
            for deviceInfo in deviceErrors.keys() {
                guard let error = deviceErrors[deviceInfo] else { continue }
                
                anyErrors = true
                print(describeError(error, forDevice: deviceInfo), toStream: &stderr)
            }
            
            if anyErrors {
                print("\n\(errorContactInstruction())", toStream: &stderr)
            }
            })
    }
    
}
