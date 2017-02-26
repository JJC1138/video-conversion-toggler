import Foundation

func runRunLoopUntilAllOperationsAreFinished(onQueue queue: OperationQueue) {
    let runLoopStopperQueue = OperationQueue()
    class RunLoopStopper: Operation {
        let queue: OperationQueue
        let runLoop: CFRunLoop
        init(queue: OperationQueue, runLoop: CFRunLoop) {
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
    UserDefaults.standard.bool(forKey: "NSShowNonLocalizedStrings")
    
    var deviceSettings = [DeviceInfo: Bool]()
    var deviceErrors = [DeviceInfo: AppError]()
    
    let operationQueue = OperationQueue()
    let resultQueue = OperationQueue()
    resultQueue.maxConcurrentOperationCount = 1 // Serialize accesses to the non-thread safe result dictionaries above.
    
    func toggleSettingAndReportResults(_ deviceInfo: DeviceInfo) {
        operationQueue.addOperation {
            do {
                let result = try toggleSetting(deviceInfo)
                resultQueue.addOperation { deviceSettings[deviceInfo] = result }
            } catch let e as AppError {
                resultQueue.addOperation { deviceErrors[deviceInfo] = e }
            } catch {}
        }
    }
    
//    toggleSettingAndReportResults(DeviceInfo(name: "Test Device", baseURL: NSURL(string: "http://192.168.255.207")!))
//    operationQueue.addOperationWithBlock { discoverSSDPServices(type: "urn:schemas-upnp-org:device:MediaRenderer:1") { print($0) } }
    operationQueue.addOperation {
        discoverCompatibleDevices { deviceInfo in
            operationQueue.addOperation {
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
        print(describeError(error, forDevice: deviceInfo), to: &stderr)
    }
    
    if anyErrors {
        print("\n\(errorContactInstruction())", to: &stderr)
        exit(1)
    }
    
    if !anyErrors && deviceSettings.isEmpty {
        print(noDevicesContactInstruction(), to: &stderr)
        exit(2)
    }
}
