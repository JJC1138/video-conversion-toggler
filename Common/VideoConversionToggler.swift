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

struct DeviceInfo: Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    let name: String
    let baseURL: NSURL
    
    var hashValue: Int { return baseURL.hashValue }
    var description: String { return name }
    var debugDescription: String { return "\(name) <\(baseURL)>" }
}
func == (a: DeviceInfo, b: DeviceInfo) -> Bool { return a.baseURL == b.baseURL }

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
    let complete = dispatch_semaphore_create(0)!
    
    var error: AppError?
    var result: Bool?
    
    af.request(.GET, NSURL(string: "SETUP/VIDEO/d_video.asp", relativeToURL: deviceInfo.baseURL)!).validate().responseData {
        response in
        
        defer { dispatch_semaphore_signal(complete) }
        
        if let responseError = response.result.error {
            error = AppError(kind: .CouldNotAccessWebInterface, nsError: responseError)
            return
        }
        
        let doc = HTMLDocument(data: response.data!, contentTypeHeader: response.response?.allHeaderFields["Content-Type"] as! String?)
        
        guard let conversionElement = doc.firstNodeMatchingSelector("input[name=\"radioVideoConvMode\"][value=\"ON\"]") else {
            error = AppError(kind: .WebInterfaceNotAsExpected, info: "Couldn't find setting input element")
            return
        }
        
        let conversionWasOn = conversionElement.attributes["checked"] != nil
        
        result = conversionWasOn
    }
    
    dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)
    
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
        locationFetches.addOperation(NSBlockOperation {
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
        })
    }
    
    locationFetches.waitUntilAllOperationsAreFinished()
}

func errorContactInstruction() -> String {
    let contact = "vidconvtoggle@jjc1138.net"
    return localString(format: localString("Please contact %@ with the above error information."), contact)
}

