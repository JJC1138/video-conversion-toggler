import Foundation

struct DeviceInfo: Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    let name: String
    let baseURL: NSURL
    
    var hashValue: Int { return baseURL.hashValue }
    var description: String { return name }
    var debugDescription: String { return "\(name) <\(baseURL)>" }
}
func == (a: DeviceInfo, b: DeviceInfo) -> Bool { return a.baseURL == b.baseURL }

class DeviceInfoCoding: NSObject, NSCoding {
    
    let deviceInfo: DeviceInfo
    
    static let nameKey = "name"
    static let baseURLKey = "baseURL"
    
    required init?(coder: NSCoder) {
        guard let name = coder.decodeObjectForKey(DeviceInfoCoding.nameKey) as? String else { return nil }
        guard let baseURL = coder.decodeObjectForKey(DeviceInfoCoding.baseURLKey) as? NSURL else { return nil }
        
        deviceInfo = DeviceInfo(name: name, baseURL: baseURL)
        super.init()
    }
    
    init(_ deviceInfo: DeviceInfo) { self.deviceInfo = deviceInfo }
    
    func encodeWithCoder(coder: NSCoder) {
        coder.encodeObject(deviceInfo.name, forKey: DeviceInfoCoding.nameKey)
        coder.encodeObject(deviceInfo.baseURL, forKey: DeviceInfoCoding.baseURLKey)
    }
    
}
