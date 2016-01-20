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

struct DeviceInfo: Hashable, CustomStringConvertible {
    let name: String
    let baseURL: NSURL
    
    var hashValue: Int { return baseURL.hashValue }
    var description: String { return name }
}
func == (a: DeviceInfo, b: DeviceInfo) -> Bool { return a.baseURL == b.baseURL }

var deviceErrors = ConcurrentDictionary<DeviceInfo, AppError>()
var deviceSettings = ConcurrentDictionary<DeviceInfo, Bool>()

func describeError(error: AppError, forDevice deviceInfo: DeviceInfo) -> String {
    let errorDescriptionFormat: String = {
        // Using a switch here allows the compiler to catch the error if we don't specify all possible values:
        switch error.kind {
        case .CouldNotAccessWebInterface, .WebInterfaceNotAsExpected, .SubmittingChangeFailed, .SettingDidNotChange:
            return localString("AppError.Kind.\(error.kind)")
        }
    }()
    
    var errorInfo = [String]()
    
    errorInfo.append(String.localizedStringWithFormat(errorDescriptionFormat, String(deviceInfo)))
    if let e = error.info { errorInfo.append(e) }
    if let e = error.nsError { errorInfo.append(e.localizedDescription) }
    
    return errorInfo.joinWithSeparator("\n\n")
}

let af = Alamofire.Manager(configuration: {
    let configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration()
    configuration.timeoutIntervalForRequest = 5
    return configuration
    }())

class FetchStatusOperation: NSOperation {
    
    let deviceInfo: DeviceInfo
    var error: AppError?
    var result: Bool?
    
    init(deviceInfo: DeviceInfo) {
        self.deviceInfo = deviceInfo
    }
    
    override func main() {
        let complete = dispatch_semaphore_create(0)!
        
        af.request(.GET, NSURL(string: "SETUP/VIDEO/d_video.asp", relativeToURL: deviceInfo.baseURL)!).validate().responseData {
            response in
            
            defer { dispatch_semaphore_signal(complete) }
            
            if let error = response.result.error {
                self.error = AppError(kind: .CouldNotAccessWebInterface, nsError: error)
                return
            }
            
            let doc = HTMLDocument(data: response.data!, contentTypeHeader: response.response?.allHeaderFields["Content-Type"] as! String?)
            
            guard let conversionElement = doc.firstNodeMatchingSelector("input[name=\"radioVideoConvMode\"][value=\"ON\"]") else {
                self.error = AppError(kind: .WebInterfaceNotAsExpected, info: "Couldn't find setting input element")
                return
            }
            
            let conversionWasOn = conversionElement.attributes["checked"] != nil
            
            self.result = conversionWasOn
        }
        
        dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)
        
        if let result = result { deviceSettings[deviceInfo] = result }
        if let error = error {
            deviceErrors[deviceInfo] = error
            if result == nil {
                // We couldn't retrieve it properly, so any previously stored value might well be wrong. We should remove it to avoid showing potentially wrong information.
                deviceSettings[deviceInfo] = nil
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
        
        af.request(.POST, NSURL(string: "SETUP/VIDEO/s_video.asp", relativeToURL: deviceInfo.baseURL)!, parameters: ["radioVideoConvMode": setting ? "ON" : "OFF"]).validate().responseData {
            response in
            
            defer { dispatch_semaphore_signal(complete) }
            
            if let error = response.result.error {
                self.error = AppError(kind: .CouldNotAccessWebInterface, nsError: error)
                return
            }
        }
        
        dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER)
        
        if let error = error { deviceErrors[deviceInfo] = error }
    }
    
}

func toggleSetting(deviceInfo: DeviceInfo) {
    let fetch1 = FetchStatusOperation(deviceInfo: deviceInfo)
    fetch1.start()
    fetch1.waitUntilFinished()
    guard let setting1 = fetch1.result else { return }
    
    let set = SetSettingOperation(deviceInfo: deviceInfo, setting: !setting1)
    set.start()
    set.waitUntilFinished()
    guard set.error == nil else { return }
    
    let fetch2 = FetchStatusOperation(deviceInfo: deviceInfo)
    fetch2.start()
    fetch2.waitUntilFinished()
    guard let setting2 = fetch2.result else { return }
    
    if (setting1 == setting2) {
        deviceErrors[deviceInfo] = AppError(kind: .SettingDidNotChange)
        return
    }
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
