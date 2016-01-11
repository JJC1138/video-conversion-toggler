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

// From http://stackoverflow.com/a/24103086
func synced(lock: AnyObject, closure: () -> ()) {
    objc_sync_enter(lock)
    defer { objc_sync_exit(lock) }
    closure()
}

struct DeviceInfo: Hashable, CustomStringConvertible {
    let hostname: String
    
    var hashValue: Int { return hostname.hashValue }
    var description: String { return hostname }
}
func == (a: DeviceInfo, b: DeviceInfo) -> Bool { return a.hostname == b.hostname }

enum DeviceStatus {
    case SettingRetrieved(Bool)
    case Error(AppError)
}

struct DevicesStatuses {
    private var statuses = [DeviceInfo: DeviceStatus]()
    private var statusesLock = NSObject()
    subscript(deviceInfo: DeviceInfo) -> DeviceStatus? {
        get {
            objc_sync_enter(statusesLock)
            defer { objc_sync_exit(statusesLock) }
            return self.statuses[deviceInfo]
        }
        set {
            synced(statusesLock) {
                self.statuses[deviceInfo] = newValue
            }
        }
    }
    func devices() -> [DeviceInfo] {
        objc_sync_enter(statusesLock)
        defer { objc_sync_exit(statusesLock) }
        return [DeviceInfo](self.statuses.keys)
    }
}
var deviceStatuses = DevicesStatuses()

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
            return "Found device %@ and tried to change setting, but it didn't update. Is the device switched off?"
        }
    }()
    
    var errorInfo = [String]()
    
    errorInfo.append(String.localizedStringWithFormat(errorDescriptionFormat, String(deviceInfo)))
    if let e = error.info { errorInfo.append(e) }
    if let e = error.nsError { errorInfo.append(e.localizedDescription) }
    if let e = error.unexpectedHTTPStatus { errorInfo.append(String.localizedStringWithFormat("HTTP status %d", e)) }
    
    return errorInfo.joinWithSeparator("\n\n")
}

// From http://stackoverflow.com/a/25226794
class StandardErrorOutputStream: OutputStreamType {
    func write(string: String) {
        NSFileHandle.fileHandleWithStandardError().writeData(string.dataUsingEncoding(NSUTF8StringEncoding)!)
    }
}
var stderr = StandardErrorOutputStream()

let session: NSURLSession = {
    let configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration()
    configuration.timeoutIntervalForRequest = 5
    
    return NSURLSession(configuration: configuration)
}()

class FetchStatusOperation: NSOperation {
    
    let deviceInfo: DeviceInfo
    var result: DeviceStatus?
    
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
                self.result = .Error(AppError(kind: .CouldNotAccessWebInterface, nsError: error))
                return
            }
            
            guard let response = response as? NSHTTPURLResponse else {
                // I'm not sure if this is possible, but the docs aren't explicit.
                self.result = .Error(AppError(kind: .CouldNotAccessWebInterface))
                return
            }
            
            guard response.statusCode == 200 else {
                self.result = .Error(AppError(kind: .WebInterfaceNotAsExpected, unexpectedHTTPStatus: response.statusCode))
                return
            }
            
            guard let data = data else {
                // I'm not sure if this is possible, but the docs aren't explicit.
                self.result = .Error(AppError(kind: .WebInterfaceNotAsExpected, info: "No data received"))
                return
            }
            
            let doc = HTMLDocument(data: data, contentTypeHeader: response.allHeaderFields["Content-Type"] as! String?)
            
            guard let conversionElement = doc.firstNodeMatchingSelector("input[name=\"radioVideoConvMode\"][value=\"ON\"]") else {
                self.result = .Error(AppError(kind: .WebInterfaceNotAsExpected, info: "Couldn't find setting input element"))
                return
            }
            
            let conversionWasOn = conversionElement.attributes["checked"] != nil
            
            self.result = .SettingRetrieved(conversionWasOn)
        }).resume()
        
        dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)
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
        // FIXME implement
    }
    
}

class ToggleSettingOperation: NSOperation {
    
    let deviceInfo: DeviceInfo
    var result: DeviceStatus?
    
    init(deviceInfo: DeviceInfo) {
        self.deviceInfo = deviceInfo
    }
    
    override func main() {
        let fetch1 = FetchStatusOperation(deviceInfo: deviceInfo)
        fetch1.start()
        fetch1.waitUntilFinished()
        
        guard let setting1: Bool = {
            switch fetch1.result! {
            case .Error(let e):
                result = .Error(e)
                return nil
            case .SettingRetrieved(let setting):
                return setting
            }
            }() else { return }
        
        let set = SetSettingOperation(deviceInfo: deviceInfo, setting: !setting1)
        set.start()
        set.waitUntilFinished()
        if let e = set.error {
            result = .Error(e)
            return
        }
        
        let fetch2 = FetchStatusOperation(deviceInfo: deviceInfo)
        fetch2.start()
        fetch2.waitUntilFinished()
        
        guard let setting2: Bool = {
            switch fetch2.result! {
            case .Error(let e):
                result = .Error(e)
                return nil
            case .SettingRetrieved(let setting):
                return setting
            }
            }() else { return }
        
        if (setting1 == setting2) {
            result = .Error(AppError(kind: .SettingDidNotChange))
            return
        }
        
        result = .SettingRetrieved(setting2)
    }

}

var operationQueue = NSOperationQueue()

operationQueue.addOperation(ToggleSettingOperation(deviceInfo: DeviceInfo(hostname: Process.arguments[1])))

operationQueue.waitUntilAllOperationsAreFinished()

do {
    let deviceInfos = deviceStatuses.devices()
    var anyErrors = false
    for deviceInfo in deviceInfos {
        guard let status = deviceStatuses[deviceInfo] else { continue }
        
        switch status {
        case .SettingRetrieved(let setting):
            print("\(deviceInfo): \(setting ? "on" : "off")")
        case .Error(let e):
            anyErrors = true
            print(describeError(e, forDevice: deviceInfo), toStream: &stderr)
        }
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
