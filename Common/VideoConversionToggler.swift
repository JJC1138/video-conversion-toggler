import Foundation

import Alamofire
import Fuzi
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
    init(kind: Kind, info: String? = nil, nsError: NSError? = nil) {
        self.kind = kind
        self.info = info
        self.nsError = nsError
    }
}

func describeError(error: AppError, forDevice deviceInfo: DeviceInfo) -> String {
    let errorDescriptionFormat: String = {
        // Using a switch here allows the compiler to catch the error if we don't specify all possible values:
        switch error.kind {
        case .CouldNotAccessWebInterface, .WebInterfaceNotAsExpected, .SubmittingChangeFailed, .SettingDidNotChange:
            return localString("AppError.Kind.\(error.kind)")
        }
    }()
    
    var errorInfo = [String]()
    
    errorInfo.append(localString(format: errorDescriptionFormat, deviceInfo.debugDescription))
    if let e = error.info { errorInfo.append(e) }
    if let e = error.nsError { errorInfo.append(e.localizedDescription) }
    
    return errorInfo.joinWithSeparator("\n\n")
}

let af = Alamofire.Manager(configuration: {
    let configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration()
    configuration.timeoutIntervalForRequest = 5
    return configuration
    }())

func fetchSetting(deviceInfo: DeviceInfo) throws -> Bool {
    var error: AppError?
    var result: Bool?
    
    do {
        let complete = dispatch_semaphore_create(0)!
        // We have to request this page first to initialize something in the web interface. If we don't then the d_video request below can sometimes return a page where neither of the setting's radio buttons are checked.
        af.request(.GET, NSURL(string: "SETUP/VIDEO/r_video.asp", relativeToURL: deviceInfo.baseURL)!).validate().responseData {
            response in
            
            defer { dispatch_semaphore_signal(complete) }
            
            if let responseError = response.result.error {
                error = AppError(kind: .CouldNotAccessWebInterface, nsError: responseError)
                return
            }
        }
        dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)
    }
    
    if error == nil {
        let complete = dispatch_semaphore_create(0)!
        af.request(.GET, NSURL(string: "SETUP/VIDEO/d_video.asp", relativeToURL: deviceInfo.baseURL)!).validate().responseData {
            response in
            
            defer { dispatch_semaphore_signal(complete) }
            
            if let responseError = response.result.error {
                error = AppError(kind: .CouldNotAccessWebInterface, nsError: responseError)
                return
            }
            
            let doc = HTMLDocument(data: response.data!, contentTypeHeader: response.response?.allHeaderFields["Content-Type"] as! String?)
            
            guard let
                conversionOnElement = doc.firstNodeMatchingSelector("input[name=\"radioVideoConvMode\"][value=\"ON\"]"),
                conversionOffElement = doc.firstNodeMatchingSelector("input[name=\"radioVideoConvMode\"][value=\"OFF\"]") else {
                    
                error = AppError(kind: .WebInterfaceNotAsExpected, info: "Couldn't find setting input element")
                return
            }
            
            func isChecked(element: HTMLElement) -> Bool { return element.attributes["checked"] != nil }
            
            let conversionOnChecked = isChecked(conversionOnElement)
            let conversionOffChecked = isChecked(conversionOffElement)
            
            guard conversionOnChecked != conversionOffChecked else {
                error = AppError(kind: .WebInterfaceNotAsExpected, info: "Setting on and off elements had same value")
                return
            }
            
            // TESTING uncomment to produce intermittent errors:
//            guard Int(awakeUptime()) % 3 != 0 else {
//                error = AppError(kind: .WebInterfaceNotAsExpected, info: "Fake test error")
//                return
//            }
            
            let conversionWasOn = conversionOnChecked
            
            result = conversionWasOn
        }
        dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)
    }
    
    if let error = error { throw error }
    return result!
}

func setSetting(deviceInfo: DeviceInfo, setting: Bool) throws {
    let complete = dispatch_semaphore_create(0)!
    
    var error: AppError?
    
    af.request(.POST, NSURL(string: "SETUP/VIDEO/s_video.asp", relativeToURL: deviceInfo.baseURL)!, parameters: ["radioVideoConvMode": setting ? "ON" : "OFF"]).validate().responseData {
        response in
        
        defer { dispatch_semaphore_signal(complete) }
        
        if let responseError = response.result.error {
            error = AppError(kind: .CouldNotAccessWebInterface, nsError: responseError)
            return
        }
    }
    
    dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)
    
    if let error = error { throw error }
}

func toggleSetting(deviceInfo: DeviceInfo) throws -> Bool {
    let setting1 = try fetchSetting(deviceInfo)
    try setSetting(deviceInfo, setting: !setting1)
    let setting2 = try fetchSetting(deviceInfo)
    
    if (setting1 == setting2) { throw AppError(kind: .SettingDidNotChange) }
    return setting2
}

func discoverCompatibleDevices(delegate: DeviceInfo -> Void) {
    let locationFetches = NSOperationQueue()
    
    discoverSSDPServices(type: "urn:schemas-upnp-org:device:MediaRenderer:1") { ssdpResponse in
        locationFetches.addOperationWithBlock {
            let complete = dispatch_semaphore_create(0)!
            
            af.request(.GET, ssdpResponse.location).validate().responseData { httpResponse in
                defer { dispatch_semaphore_signal(complete) }
                
                guard let xml: XMLDocument = {
                    guard let data = httpResponse.data else { return nil }
                    return try? XMLDocument(data: data)
                    }() else { return }
                
                guard let deviceTag = xml.root?.firstChild(tag: "device") else { return }
                
                guard let manufacturer = deviceTag.firstChild(tag: "manufacturer")?.stringValue else { return }
                
                guard ["Denon", "Marantz"].contains(manufacturer) else { return }
                
                guard let presentationURLTag = deviceTag.firstChild(tag: "presentationURL") else { return }
                
                guard let presentationURL = NSURL(string: presentationURLTag.stringValue, relativeToURL: ssdpResponse.location) else { return }
                
                guard let friendlyName = deviceTag.firstChild(tag: "friendlyName")?.stringValue else { return }
                
                let deviceInfo = DeviceInfo(name: friendlyName, baseURL: presentationURL)
                
                delegate(deviceInfo)
            }
            
            dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)
        }
    }
    
    locationFetches.waitUntilAllOperationsAreFinished()
}

let contact = "vidconvtoggle@jjc1138.net"

func errorContactInstruction() -> String {
    return localString(format: localString("Please contact %@ with the above error information."), contact)
}

func noDevicesContactInstruction() -> String {
    return localString(format: localString("No devices found."), contact)
}

class PeriodicallyFetchAllStatuses: NSOperation {
    
    init(delegateQueue: NSOperationQueue = NSOperationQueue.mainQueue(), fetchErrorDelegate: (DeviceInfo, AppError) -> Void, fetchResultDelegate: (DeviceInfo, Bool) -> Void) {
        // FUTURETODO replace with memberwise init when that exists
        self.delegateQueue = delegateQueue
        self.fetchErrorDelegate = fetchErrorDelegate
        self.fetchResultDelegate = fetchResultDelegate
    }
    
    let delegateQueue: NSOperationQueue
    let fetchErrorDelegate: (DeviceInfo, AppError) -> Void
    let fetchResultDelegate: (DeviceInfo, Bool) -> Void
    
    override func main() {
        let fetchQueue = NSOperationQueue()
        while (!cancelled) {
            fetchAllStatuses(delegateQueue: delegateQueue, fetchQueue: fetchQueue, fetchErrorDelegate: fetchErrorDelegate, fetchResultDelegate: fetchResultDelegate)
        }
        fetchQueue.waitUntilAllOperationsAreFinished()
    }
    
}

func fetchAllStatuses(delegateQueue delegateQueue: NSOperationQueue = NSOperationQueue.mainQueue(), fetchQueue: NSOperationQueue, fetchErrorDelegate: (DeviceInfo, AppError) -> Void, fetchResultDelegate: (DeviceInfo, Bool) -> Void) {
    discoverCompatibleDevices { deviceInfo in fetchQueue.addOperationWithBlock {
        do {
            let setting = try fetchSetting(deviceInfo)
            delegateQueue.addOperationWithBlock { fetchResultDelegate(deviceInfo, setting) }
        } catch let e as AppError {
            delegateQueue.addOperationWithBlock { fetchErrorDelegate(deviceInfo, e) }
        } catch { assert(false) }
        }
    }
}

func fetchAllStatusesOnce(delegateQueue delegateQueue: NSOperationQueue = NSOperationQueue.mainQueue(), fetchErrorDelegate: (DeviceInfo, AppError) -> Void, fetchResultDelegate: (DeviceInfo, Bool) -> Void) {
    let fetchQueue = NSOperationQueue()
    fetchAllStatuses(delegateQueue: delegateQueue, fetchQueue: fetchQueue, fetchErrorDelegate: fetchErrorDelegate, fetchResultDelegate: fetchResultDelegate)
    fetchQueue.waitUntilAllOperationsAreFinished()
}
