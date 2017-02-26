import Foundation

struct DeviceInfo: Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    let name: String
    let baseURL: URL
    
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
        guard let name = coder.decodeObject(forKey: DeviceInfoCoding.nameKey) as? String else { return nil }
        guard let baseURL = coder.decodeObject(forKey: DeviceInfoCoding.baseURLKey) as? URL else { return nil }
        
        deviceInfo = DeviceInfo(name: name, baseURL: baseURL)
        super.init()
    }
    
    init(_ deviceInfo: DeviceInfo) { self.deviceInfo = deviceInfo }
    
    func encode(with coder: NSCoder) {
        coder.encode(deviceInfo.name, forKey: DeviceInfoCoding.nameKey)
        coder.encode(deviceInfo.baseURL, forKey: DeviceInfoCoding.baseURLKey)
    }
    
}
