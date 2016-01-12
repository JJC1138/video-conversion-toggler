import Foundation

import HTMLReader

struct AppError : ErrorType {
    enum Kind {
        case CouldNotAccessWebInterface
        case WebInterfaceNotAsExpected
        case SubmittingChangeFailed
        case SettingDidNotChange
    }
    let kind: Kind
    let info: String?
    let nsError: NSError?
    let unexpectedHTTPStatus: Int?
    init(kind: Kind, info: String? = nil, nsError: NSError? = nil, unexpectedHTTPStatus: Int? = nil) {
        self.kind = kind
        self.info = info
        self.nsError = nsError
        self.unexpectedHTTPStatus = unexpectedHTTPStatus
    }
}

struct DeviceInfo: Hashable, CustomStringConvertible {
    let hostname: String
    
    var hashValue: Int { return hostname.hashValue }
    var description: String { return hostname }
}
func == (a: DeviceInfo, b: DeviceInfo) -> Bool { return a.hostname == b.hostname }

var deviceErrors = ConcurrentDictionary<DeviceInfo, AppError>()
var deviceSettings = ConcurrentDictionary<DeviceInfo, Bool>()

func describeError(error: AppError, forDevice deviceInfo: DeviceInfo) -> String {
    // LOCALIZE all strings
    let errorDescriptionFormat: String = {
        switch error.kind {
        case .CouldNotAccessWebInterface:
            return "Found device %@ but couldn't access web interface."
        case .WebInterfaceNotAsExpected:
            return "Found device %@ but web interface wasn't as expected."
        case .SubmittingChangeFailed:
            return "Found device %@ and accessed web interface but changing setting failed."
        case .SettingDidNotChange:
            return "Found device %@ and tried to change setting, but it didn't update. That can happen if the device is switched off, so please check if it is on."
        }
    }()
    
    var errorInfo = [String]()
    
    errorInfo.append(String.localizedStringWithFormat(errorDescriptionFormat, String(deviceInfo)))
    if let e = error.info { errorInfo.append(e) }
    if let e = error.nsError { errorInfo.append(e.localizedDescription) }
    if let e = error.unexpectedHTTPStatus { errorInfo.append(String.localizedStringWithFormat("HTTP status %d", e)) }
    
    return errorInfo.joinWithSeparator("\n\n")
}

let session: NSURLSession = {
    let configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration()
    configuration.timeoutIntervalForRequest = 5
    
    return NSURLSession(configuration: configuration)
}()

class FetchStatusOperation: NSOperation {
    
    let deviceInfo: DeviceInfo
    var error: AppError?
    var result: Bool?
    
    init(deviceInfo: DeviceInfo) {
        self.deviceInfo = deviceInfo
    }
    
    override func main() {
        let complete = dispatch_semaphore_create(0)!
        
        let configPageURL = NSURL(string: "http://\(deviceInfo.hostname)/SETUP/VIDEO/d_video.asp")!
        
        session.dataTaskWithURL(configPageURL, completionHandler: {
            data, response, error in
            
            defer { dispatch_semaphore_signal(complete) }
            
            if let error = error {
                self.error = AppError(kind: .CouldNotAccessWebInterface, nsError: error)
                return
            }
            
            guard let response = response as? NSHTTPURLResponse else {
                // I'm not sure if this is possible, but the docs aren't explicit.
                self.error = AppError(kind: .CouldNotAccessWebInterface)
                return
            }
            
            guard response.statusCode == 200 else {
                self.error = AppError(kind: .WebInterfaceNotAsExpected, unexpectedHTTPStatus: response.statusCode)
                return
            }
            
            let doc = HTMLDocument(data: data!, contentTypeHeader: response.allHeaderFields["Content-Type"] as! String?)
            
            guard let conversionElement = doc.firstNodeMatchingSelector("input[name=\"radioVideoConvMode\"][value=\"ON\"]") else {
                self.error = AppError(kind: .WebInterfaceNotAsExpected, info: "Couldn't find setting input element")
                return
            }
            
            let conversionWasOn = conversionElement.attributes["checked"] != nil
            
            self.result = conversionWasOn
        }).resume()
        
        dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)
        
        if let result = self.result { deviceSettings[self.deviceInfo] = result }
        if let error = self.error {
            deviceErrors[self.deviceInfo] = error
            if self.result == nil {
                // We couldn't retrieve it properly, so any previously stored value might well be wrong. We should remove it to avoid showing potentially wrong information.
                deviceSettings[self.deviceInfo] = nil
            }
        }
    }
    
}

class SetSettingOperation: NSOperation {
    
    let deviceInfo: DeviceInfo
    let setting: Bool
    var error: AppError?
    
    init(deviceInfo: DeviceInfo, setting: Bool) {
        self.deviceInfo = deviceInfo
        self.setting = setting
    }
    
    override func main() {
        let complete = dispatch_semaphore_create(0)!
        
        let setConfigRequest = NSURLRequest(URL: NSURL(string: "http://\(deviceInfo.hostname)/SETUP/VIDEO/s_video.asp")!)
        
        let data = NSData()
        // FIXME populate data
        
        session.uploadTaskWithRequest(setConfigRequest, fromData: data, completionHandler: {
            data, response, error in
            
            defer { dispatch_semaphore_signal(complete) }
            
            if let error = error {
                self.error = AppError(kind: .CouldNotAccessWebInterface, nsError: error)
                return
            }
            
            guard let response = response as? NSHTTPURLResponse else {
                // I'm not sure if this is possible, but the docs aren't explicit.
                self.error = AppError(kind: .CouldNotAccessWebInterface)
                return
            }
            
            guard response.statusCode == 200 else {
                self.error = AppError(kind: .WebInterfaceNotAsExpected, unexpectedHTTPStatus: response.statusCode)
                return
            }
        }).resume()
        
        dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)
        
        if let error = self.error { deviceErrors[self.deviceInfo] = error }
    }
    
}

class ToggleSettingOperation: NSOperation {
    
    let deviceInfo: DeviceInfo
    
    init(deviceInfo: DeviceInfo) {
        self.deviceInfo = deviceInfo
    }
    
    override func main() {
        let fetch1 = FetchStatusOperation(deviceInfo: self.deviceInfo)
        fetch1.start()
        fetch1.waitUntilFinished()
        guard let setting1 = fetch1.result else { return }
        
        let set = SetSettingOperation(deviceInfo: self.deviceInfo, setting: !setting1)
        set.start()
        set.waitUntilFinished()
        guard set.error == nil else { return }
        
        let fetch2 = FetchStatusOperation(deviceInfo: self.deviceInfo)
        fetch2.start()
        fetch2.waitUntilFinished()
        guard let setting2 = fetch2.result else { return }
        
        if (setting1 == setting2) {
            deviceErrors[self.deviceInfo] = AppError(kind: .SettingDidNotChange)
            return
        }
    }
    
}
