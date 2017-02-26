import Foundation

import Alamofire
import Fuzi
import HTMLReader

struct AppError : Error {
    enum Kind {
        case couldNotAccessWebInterface
        case webInterfaceNotAsExpected
        case submittingChangeFailed
        case settingDidNotChange
    }
    let kind: Kind
    let info: String?
    let cause: Error?
    init(kind: Kind, info: String? = nil, cause: Error? = nil) {
        self.kind = kind
        self.info = info
        self.cause = cause
    }
}

func describeError(_ error: AppError, forDevice deviceInfo: DeviceInfo) -> String {
    let errorDescriptionFormat: String = {
        // Using a switch here allows the compiler to catch the error if we don't specify all possible values:
        switch error.kind {
        case .couldNotAccessWebInterface, .webInterfaceNotAsExpected, .submittingChangeFailed, .settingDidNotChange:
            return localString("AppError.Kind.\(error.kind)")
        }
    }()
    
    var errorInfo = [String]()
    
    errorInfo.append(localString(format: errorDescriptionFormat, deviceInfo.debugDescription))
    if let info = error.info { errorInfo.append(info) }
    if let cause = error.cause { errorInfo.append(cause.localizedDescription) }
    
    return errorInfo.joined(separator: "\n\n")
}

let af = Alamofire.SessionManager(configuration: {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 5
    return configuration
    }())

func fetchSetting(_ deviceInfo: DeviceInfo) throws -> Bool {
    var error: AppError?
    var result: Bool?
    
    do {
        let complete = DispatchSemaphore(value: 0)
        // We have to request this page first to initialize something in the web interface. If we don't then the d_video request below can sometimes return a page where neither of the setting's radio buttons are checked.
        af.request(URL(string: "SETUP/VIDEO/r_video.asp", relativeTo: deviceInfo.baseURL)!).validate().responseData {
            response in
            
            defer { complete.signal() }
            
            if let responseError = response.result.error {
                error = AppError(kind: .couldNotAccessWebInterface, cause: responseError)
                return
            }
        }
        _ = complete.wait(timeout: DispatchTime.distantFuture)
    }
    
    if error == nil {
        let complete = DispatchSemaphore(value: 0)
        af.request(URL(string: "SETUP/VIDEO/d_video.asp", relativeTo: deviceInfo.baseURL)!).validate().responseData {
            response in
            
            defer { complete.signal() }
            
            if let responseError = response.result.error {
                error = AppError(kind: .couldNotAccessWebInterface, cause: responseError)
                return
            }
            
            let doc = HTMLDocument(data: response.data!, contentTypeHeader: response.response?.allHeaderFields["Content-Type"] as! String?)
            
            guard let
                conversionOnElement = doc.firstNode(matchingSelector: "input[name=\"radioVideoConvMode\"][value=\"ON\"]"),
                let conversionOffElement = doc.firstNode(matchingSelector: "input[name=\"radioVideoConvMode\"][value=\"OFF\"]") else {
                    
                error = AppError(kind: .webInterfaceNotAsExpected, info: "Couldn't find setting input element")
                return
            }
            
            func isChecked(_ element: HTMLElement) -> Bool { return element.attributes["checked"] != nil }
            
            let conversionOnChecked = isChecked(conversionOnElement)
            let conversionOffChecked = isChecked(conversionOffElement)
            
            guard conversionOnChecked != conversionOffChecked else {
                error = AppError(kind: .webInterfaceNotAsExpected, info: "Setting on and off elements had same value")
                return
            }
            
            // TESTING uncomment to produce intermittent errors:
//            guard Int(awakeUptime()) % 3 != 0 else {
//                error = AppError(kind: .webInterfaceNotAsExpected, info: "Fake test error")
//                return
//            }
            
            let conversionWasOn = conversionOnChecked
            
            result = conversionWasOn
        }
        _ = complete.wait(timeout: DispatchTime.distantFuture)
    }
    
    if let error = error { throw error }
    return result!
}

func setSetting(_ deviceInfo: DeviceInfo, setting: Bool) throws {
    let complete = DispatchSemaphore(value: 0)
    
    var error: AppError?
    
    af.request(URL(string: "SETUP/VIDEO/s_video.asp", relativeTo: deviceInfo.baseURL)!, method: .post, parameters: ["radioVideoConvMode": setting ? "ON" : "OFF"]).validate().responseData {
        response in
        
        defer { complete.signal() }
        
        if let responseError = response.result.error {
            error = AppError(kind: .couldNotAccessWebInterface, cause: responseError)
            return
        }
    }
    
    _ = complete.wait(timeout: DispatchTime.distantFuture)
    
    if let error = error { throw error }
}

func toggleSetting(_ deviceInfo: DeviceInfo) throws -> Bool {
    let setting1 = try fetchSetting(deviceInfo)
    try setSetting(deviceInfo, setting: !setting1)
    let setting2 = try fetchSetting(deviceInfo)
    
    if (setting1 == setting2) { throw AppError(kind: .settingDidNotChange) }
    return setting2
}

func discoverCompatibleDevices(_ delegate: @escaping (DeviceInfo) -> Void) {
    let locationFetches = OperationQueue()
    
    discoverSSDPServices(type: "urn:schemas-upnp-org:device:MediaRenderer:1") { ssdpResponse in
        locationFetches.addOperation {
            let complete = DispatchSemaphore(value: 0)
            
            af.request(ssdpResponse.location).validate().responseData { httpResponse in
                defer { complete.signal() }
                
                guard let xml: Fuzi.XMLDocument = {
                    guard let data = httpResponse.data else { return nil }
                    return try? Fuzi.XMLDocument(data: data)
                    }() else { return }
                
                guard let deviceTag = xml.root?.firstChild(tag: "device") else { return }
                
                guard let manufacturer = deviceTag.firstChild(tag: "manufacturer")?.stringValue else { return }
                
                guard ["Denon", "Marantz"].contains(manufacturer) else { return }
                
                guard let presentationURLTag = deviceTag.firstChild(tag: "presentationURL") else { return }
                
                guard let presentationURL = URL(string: presentationURLTag.stringValue, relativeTo: ssdpResponse.location) else { return }
                
                guard let friendlyName = deviceTag.firstChild(tag: "friendlyName")?.stringValue else { return }
                
                let deviceInfo = DeviceInfo(name: friendlyName, baseURL: presentationURL)
                
                delegate(deviceInfo)
            }
            
            _ = complete.wait(timeout: DispatchTime.distantFuture)
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

class PeriodicallyFetchAllStatuses: Operation {
    
    init(delegateQueue: OperationQueue = OperationQueue.main, fetchErrorDelegate: @escaping (DeviceInfo, AppError) -> Void, fetchResultDelegate: @escaping (DeviceInfo, Bool) -> Void) {
        // FUTURETODO replace with memberwise init when that exists
        self.delegateQueue = delegateQueue
        self.fetchErrorDelegate = fetchErrorDelegate
        self.fetchResultDelegate = fetchResultDelegate
    }
    
    let delegateQueue: OperationQueue
    let fetchErrorDelegate: (DeviceInfo, AppError) -> Void
    let fetchResultDelegate: (DeviceInfo, Bool) -> Void
    
    override func main() {
        let fetchQueue = OperationQueue()
        while (!isCancelled) {
            fetchAllStatuses(delegateQueue: delegateQueue, fetchQueue: fetchQueue, fetchErrorDelegate: fetchErrorDelegate, fetchResultDelegate: fetchResultDelegate)
        }
        fetchQueue.waitUntilAllOperationsAreFinished()
    }
    
}

func fetchAllStatuses(delegateQueue: OperationQueue = OperationQueue.main, fetchQueue: OperationQueue, fetchErrorDelegate: @escaping (DeviceInfo, AppError) -> Void, fetchResultDelegate: @escaping (DeviceInfo, Bool) -> Void) {
    discoverCompatibleDevices { deviceInfo in fetchQueue.addOperation {
        do {
            let setting = try fetchSetting(deviceInfo)
            delegateQueue.addOperation { fetchResultDelegate(deviceInfo, setting) }
        } catch let e as AppError {
            delegateQueue.addOperation { fetchErrorDelegate(deviceInfo, e) }
        } catch { assert(false) }
        }
    }
}

func fetchAllStatusesOnce(delegateQueue: OperationQueue = OperationQueue.main, fetchErrorDelegate: @escaping (DeviceInfo, AppError) -> Void, fetchResultDelegate: @escaping (DeviceInfo, Bool) -> Void) {
    let fetchQueue = OperationQueue()
    fetchAllStatuses(delegateQueue: delegateQueue, fetchQueue: fetchQueue, fetchErrorDelegate: fetchErrorDelegate, fetchResultDelegate: fetchResultDelegate)
    fetchQueue.waitUntilAllOperationsAreFinished()
}
