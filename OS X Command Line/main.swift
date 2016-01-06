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

var errors = [String: AppError]()
var errorsLock = NSObject()

func describeError(deviceInfo: String, error: AppError) -> String {
    // LOCALIZE all strings
    
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

// From http://stackoverflow.com/a/24103086
func synced(lock: AnyObject, closure: () -> ()) {
    objc_sync_enter(lock)
    defer { objc_sync_exit(lock) }
    closure()
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

let sessionConfiguration = NSURLSessionConfiguration.ephemeralSessionConfiguration()
sessionConfiguration.timeoutIntervalForRequest = 5

let session = NSURLSession(configuration: sessionConfiguration)

let complete = dispatch_semaphore_create(0)!

session.dataTaskWithURL(configPageURL, completionHandler: {
    data, response, error in
    
    defer { dispatch_semaphore_signal(complete) }
    
    print("completion") // FIXME
    
    if let error = error {
        synced(errorsLock) {
            errors[deviceHostname] = AppError(kind: .CouldNotAccessWebInterface, error: error)
        }
    }
}).resume()

dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)

synced(errorsLock) {
    for (deviceHostname, error) in errors {
        print(describeError(deviceHostname, error: error), toStream: &stderr)
    }
}
