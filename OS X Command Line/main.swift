import Foundation

import HTMLReader

struct AppError : ErrorType {
    enum Kind {
        case CouldNotAccessWebInterface
        case WebInterfaceNotAsExpected
        case SubmittingChangeFailed
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

enum DeviceStatus {
    case SettingOn
    case SettingOff
    case Error(AppError)
}

struct DevicesStatuses {
    private var statuses = [String: DeviceStatus]()
    private var statusesLock = NSObject()
    subscript(deviceInfo: String) -> DeviceStatus? {
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
    func devices() -> [String] {
        objc_sync_enter(statusesLock)
        defer { objc_sync_exit(statusesLock) }
        return [String](self.statuses.keys)
    }
}
var deviceStatuses = DevicesStatuses()

func describeError(deviceInfo: String) -> String? {
    // LOCALIZE all strings
    guard let status = deviceStatuses[deviceInfo] else { return nil }
    
    guard let error: AppError = {
        switch status {
        case .Error(let e): return e
        default: return nil
        }
        }() else { return nil }
    
    let errorDescriptionFormat: String = {
        switch error.kind {
        case .CouldNotAccessWebInterface:
            return "Found device %@ but couldn't access web interface."
        case .WebInterfaceNotAsExpected:
            return "Found device %@ but web interface wasn't as expected."
        case .SubmittingChangeFailed:
            return "Found device %@ and accessed web interface but changing setting failed."
        }
    }()
    
    var errorInfo = [String]()
    
    errorInfo.append(String.localizedStringWithFormat(errorDescriptionFormat, deviceInfo))
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

let deviceHostname = Process.arguments[1]
let configPageURL = NSURL(string: "http://\(deviceHostname)/SETUP/VIDEO/d_video.asp")!

let session: NSURLSession = {
    let configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration()
    configuration.timeoutIntervalForRequest = 5
    
    return NSURLSession(configuration: configuration)
}()

let complete = dispatch_semaphore_create(0)!

session.dataTaskWithURL(configPageURL, completionHandler: {
    data, response, error in
    
    defer { dispatch_semaphore_signal(complete) }
    
    if let error = error {
        deviceStatuses[deviceHostname] = .Error(AppError(kind: .CouldNotAccessWebInterface, nsError: error))
    }
    
    guard let response = response as? NSHTTPURLResponse else {
        // I'm not sure if this is possible, but the docs aren't explicit.
        deviceStatuses[deviceHostname] = .Error(AppError(kind: .CouldNotAccessWebInterface))
        return
    }
    
    guard response.statusCode == 200 else {
        deviceStatuses[deviceHostname] = .Error(AppError(kind: .WebInterfaceNotAsExpected, unexpectedHTTPStatus: response.statusCode))
        return
    }
    
    guard let data = data else {
        // I'm not sure if this is possible, but the docs aren't explicit.
        deviceStatuses[deviceHostname] = .Error(AppError(kind: .WebInterfaceNotAsExpected, info: "No data received"))
        return
    }
    
    let doc = HTMLDocument(data: data, contentTypeHeader: response.allHeaderFields["Content-Type"] as! String?)
    
    guard let conversionElement = doc.firstNodeMatchingSelector("input[name=\"radioVideoConvMode\"][value=\"ON\"]") else {
        deviceStatuses[deviceHostname] = .Error(AppError(kind: .WebInterfaceNotAsExpected, info: "Couldn't find setting input element"))
        return
    }
    
    let conversionWasOn = conversionElement.attributes["checked"] != nil
    print("Conversion was \(conversionWasOn ? "on" : "off")") // FIXME remove
    
    print("completion") // FIXME remove
}).resume()

dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)

do {
    let deviceInfos = deviceStatuses.devices()
    var anyErrors = false
    for deviceInfo in deviceInfos {
        if let errorInfo = describeError(deviceInfo) {
            anyErrors = true
            print(errorInfo, toStream: &stderr)
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
