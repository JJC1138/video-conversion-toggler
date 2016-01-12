import Foundation

func cli() {
    let operationQueue = NSOperationQueue()
    
    operationQueue.addOperation(ToggleSettingOperation(deviceInfo: DeviceInfo(hostname: Process.arguments[2])))
    
    operationQueue.waitUntilAllOperationsAreFinished()
    
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
        // LOCALIZE all:
        let contact = "vidconvtoggle@jjc1138.net"
        
        print(toStream: &stderr)
        print(String.localizedStringWithFormat("Please contact %@ with the above error information.", contact),
            toStream: &stderr)
        exit(1)
    }
}
