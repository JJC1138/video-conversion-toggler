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
    
    let operationQueue = NSOperationQueue()
    
//    operationQueue.addOperation(NSBlockOperation { toggleSetting(DeviceInfo(hostname: Process.arguments[2])) })
//    operationQueue.addOperation(NSBlockOperation { discoverSSDPServices(type: "urn:schemas-upnp-org:device:MediaRenderer:1") { print($0) } })
    operationQueue.addOperation(NSBlockOperation {
        discoverCompatibleDevices { deviceInfo in
            operationQueue.addOperation(NSBlockOperation {
                toggleSetting(deviceInfo)
                })
        }
        })
    
    runRunLoopUntilAllOperationsAreFinished(onQueue: operationQueue)
    
    for deviceInfo in deviceSettings.keys() {
        guard let setting = deviceSettings[deviceInfo] else { continue }
        
        print("\(deviceInfo): \(setting ? "on" : "off")")
    }
    
    var anyErrors = false
    for deviceInfo in deviceErrors.keys() {
        guard let error = deviceErrors[deviceInfo] else { continue }
        
        anyErrors = true
        print(describeError(error, forDevice: deviceInfo), toStream: &stderr)
    }
    
    if anyErrors {
        let contact = "vidconvtoggle@jjc1138.net"
        
        print(toStream: &stderr)
        print(String.localizedStringWithFormat(localString("Please contact %@ with the above error information."), contact),
            toStream: &stderr)
        exit(1)
    }
}
