import Foundation

struct DeviceSetting {
    let device: DeviceInfo
    let setting: Bool
    let retrieved: NSTimeInterval
}

enum Operation {
    case FetchSetting
    case Toggle
}

struct Error {
    let device: DeviceInfo
    let error: AppError
    let cause: Operation
}
