import Foundation

func runRunLoopUntilAllOperationsAreFinished(onQueue queue: NSOperationQueue) {
    let runLoopStopperQueue = NSOperationQueue()
    class RunLoopStopper: NSOperation {
        let queue: NSOperationQueue
        let runLoop: CFRunLoop
        init(queue: NSOperationQueue, runLoop: CFRunLoop) {
            self.queue = queue
            self.runLoop = runLoop
        }
        override func main() {
            while !CFRunLoopIsWaiting(runLoop) {
                // We need to make sure that the run loop has started. Otherwise if queue finishes quickly we could stop the run loop before we've started it, and then when it is started nothing would stop it. We really just want to know if the run loop is running, but there's no API for that. CFRunLoopIsWaiting(_) returns false if the run loop isn't running, though, so it will do.
            }
            queue.waitUntilAllOperationsAreFinished()
            CFRunLoopStop(runLoop)
        }
    }
    runLoopStopperQueue.addOperation(RunLoopStopper(queue: queue, runLoop: CFRunLoopGetCurrent()))
    CFRunLoopRun()
}

func cli() {
    // Just looking up this key does something magical to enable the checking behaviour if it should be enabled, and to make pseudo-language support work:
    NSUserDefaults.standardUserDefaults().boolForKey("NSShowNonLocalizedStrings")
    
    var deviceSettings = [DeviceInfo: Bool]()
    var deviceErrors = [DeviceInfo: AppError]()
    
    let operationQueue = NSOperationQueue()
    let resultQueue = NSOperationQueue()
    resultQueue.maxConcurrentOperationCount = 1 // Serialize accesses to the non-thread safe result dictionaries above.
    
    func toggleSettingAndReportResults(deviceInfo: DeviceInfo) {
        operationQueue.addOperationWithBlock {
            do {
                let result = try toggleSetting(deviceInfo)
                resultQueue.addOperationWithBlock { deviceSettings[deviceInfo] = result }
            } catch let e as AppError {
                resultQueue.addOperationWithBlock { deviceErrors[deviceInfo] = e }
            } catch {}
        }
    }
    
//    toggleSettingAndReportResults(DeviceInfo(name: "Test Device", baseURL: NSURL(string: "http://192.168.255.207")!))
//    operationQueue.addOperationWithBlock { discoverSSDPServices(type: "urn:schemas-upnp-org:device:MediaRenderer:1") { print($0) } }
    operationQueue.addOperationWithBlock {
        discoverCompatibleDevices { deviceInfo in
            operationQueue.addOperationWithBlock {
                toggleSettingAndReportResults(deviceInfo)
            }
        }
    }
    
    runRunLoopUntilAllOperationsAreFinished(onQueue: operationQueue)
    resultQueue.waitUntilAllOperationsAreFinished()
    
    for deviceInfo in deviceSettings.keys {
        guard let setting = deviceSettings[deviceInfo] else { continue }
        
        print("\(deviceInfo): \(localString(setting ? "On" : "Off"))")
    }
    
    var anyErrors = false
    for deviceInfo in deviceErrors.keys {
        guard let error = deviceErrors[deviceInfo] else { continue }
        
        anyErrors = true
        print(describeError(error, forDevice: deviceInfo), toStream: &stderr)
    }
    
    if anyErrors {
        print("\n\(errorContactInstruction())", toStream: &stderr)
        exit(1)
    }
}
