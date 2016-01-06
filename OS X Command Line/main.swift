import Foundation

enum ErrorKind {
    case CouldNotAccessWebInterface
    case WebInterfaceNotAsExpected
    case SubmittingChangeFailed
}

struct AppError {
    let kind: ErrorKind
    let error: NSError?
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
    
    let errorDescription = String.localizedStringWithFormat(errorDescriptionFormat, deviceInfo)
    
    let errorInfo: String = {
        if let e = error.error {
            return e.localizedDescription
        } else {
            return "[No error description]"
        }
    }()
    
    return String.localizedStringWithFormat("%@\n\nPlease contact %@ with this error information:\n\n%@",
        errorDescription, "vidconvtoggle@jjc1138.net", errorInfo)
}

// From http://stackoverflow.com/a/25226794
class StandardErrorOutputStream: OutputStreamType {
    func write(string: String) {
        NSFileHandle.fileHandleWithStandardError().writeData(string.dataUsingEncoding(NSUTF8StringEncoding)!)
    }
}
var stderr = StandardErrorOutputStream()

let deviceHostname = Process.arguments[1]
let configPageURL = NSURL(string: "http://\(deviceHostname)/SETUP/VIDEO/d_video.asp-doesnotexist")! // FIXME remove debug suffix

print(configPageURL) // FIXME remove

let session: NSURLSession = {
    let configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration()
    configuration.timeoutIntervalForRequest = 5
    
    return NSURLSession(configuration: configuration)
}()

let complete = dispatch_semaphore_create(0)!

session.dataTaskWithURL(configPageURL, completionHandler: {
    data, response, error in
    
    defer { dispatch_semaphore_signal(complete) }
    
    print("completion") // FIXME
    
    if let error = error {
        errors[deviceHostname] = AppError(kind: .CouldNotAccessWebInterface, error: error)
    }
}).resume()

dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)

for deviceInfo in errors.deviceInfos() {
    if let errorInfo = describeError(deviceInfo) { print(errorInfo, toStream: &stderr) }
}
