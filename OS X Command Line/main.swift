import Foundation

struct AppError : ErrorType {
    enum Kind {
        case CouldNotAccessWebInterface
        case WebInterfaceNotAsExpected
        case SubmittingChangeFailed
    }
    let kind: Kind
    let nsError: NSError?
    let unexpectedHTTPStatus: Int?
}

// From http://stackoverflow.com/a/24103086
func synced(lock: AnyObject, closure: () -> ()) {
    objc_sync_enter(lock)
    defer { objc_sync_exit(lock) }
    closure()
}

struct Errors {
    private var errors = [String: AppError]()
    private var errorsLock = NSObject()
    subscript(deviceInfo: String) -> AppError? {
        get {
            objc_sync_enter(errorsLock)
            defer { objc_sync_exit(errorsLock) }
            return self.errors[deviceInfo]
        }
        set {
            synced(errorsLock) {
                self.errors[deviceInfo] = newValue
            }
        }
    }
    func deviceInfos() -> [String] {
        objc_sync_enter(errorsLock)
        defer { objc_sync_exit(errorsLock) }
        return [String](errors.keys)
    }
}
var errors = Errors()

func describeError(deviceInfo: String) -> String? {
    // LOCALIZE all strings
    
    guard let error = errors[deviceInfo] else { return nil }
    
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
        errors[deviceHostname] = AppError(kind: .CouldNotAccessWebInterface, nsError: error, unexpectedHTTPStatus: nil)
    }
    
    guard let response = response as? NSHTTPURLResponse else {
        // I'm not sure if this is possible, but the docs aren't explicit.
        errors[deviceHostname] = AppError(kind: .CouldNotAccessWebInterface, nsError: nil, unexpectedHTTPStatus: nil)
        return
    }
    
    guard response.statusCode == 200 else {
        errors[deviceHostname] = AppError(kind: .WebInterfaceNotAsExpected, nsError: nil, unexpectedHTTPStatus: response.statusCode)
        return
    }
    
    print("completion") // FIXME
}).resume()

dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)

do {
    let deviceInfos = errors.deviceInfos()
    for deviceInfo in deviceInfos {
        if let errorInfo = describeError(deviceInfo) { print(errorInfo, toStream: &stderr) }
    }
    
    if !deviceInfos.isEmpty {
        // LOCALIZE all:
        let contact = "vidconvtoggle@jjc1138.net"
        
        print(toStream: &stderr)
        print(String.localizedStringWithFormat("Please contact %@ with the above error information.", contact),
            toStream: &stderr)
        exit(1)
    }
}
