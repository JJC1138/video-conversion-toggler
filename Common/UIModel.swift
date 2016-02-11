import Foundation

class Model {
    
    let delegate: ModelViewDelegate
    
    let oq = NSOperationQueue()
    var removeOldResultsTimer: NSTimer?
    
    struct DeviceSetting {
        let device: DeviceInfo
        let setting: Bool
        let retrieved: NSTimeInterval
    }
    
    struct Error {
        let device: DeviceInfo
        let error: AppError
        let cause: Operation
    }
    
    enum Operation {
        case FetchSetting
        case Toggle
    }
    
    // Only touch these from the main thread:
    var deviceSettings = [DeviceSetting]()
    var errors = [Error]()
    var lastTimeADeviceWasSeen = NSTimeInterval()
    var toggleOperationsOutstanding = Counter<DeviceInfo, Int>()
    var completedWatchToggleTime = NSTimeInterval()
    
    init(delegate: ModelViewDelegate) {
        self.delegate = delegate
    }
    
    func start() {
        lastTimeADeviceWasSeen = awakeUptime()
        oq.addOperation(PeriodicallyFetchAllStatuses(fetchErrorDelegate: { di, e in self.newOperationError(di, error: e, operation: .FetchSetting) } , fetchResultDelegate: self.newFetchResult))
        removeOldResultsTimer = {
            // FUTURETODO Use the non-string selector initialization syntax when SE-0022 is implemented:
            let t = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: "removeOldResults", userInfo: nil, repeats: true)
            t.tolerance = 3
            return t
            }()
    }
    
    func stop() {
        oq.cancelAllOperations()
        removeOldResultsTimer?.invalidate()
    }
    
    func resetErrors() {
        errors = []
        lastTimeADeviceWasSeen = awakeUptime()
        updateErrorText()
    }
    
    func newFetchResult(deviceInfo: DeviceInfo, setting: Bool) {
        lastTimeADeviceWasSeen = awakeUptime()
        let newSetting = DeviceSetting(device: deviceInfo, setting: setting, retrieved: awakeUptime())
        
        if let index = (deviceSettings.indexOf { $0.device == deviceInfo }) {
            // We already have an entry for this device.
            let oldSetting = deviceSettings[index].setting
            // We only update an existing entry if there are no toggle operations outstanding. That prevents a confusing situation where you press the switch and it changes, but then changes back because of an old fetch operation result just coming in, and then changes again a moment later to the setting you wanted.
            if oldSetting != setting && toggleOperationsOutstanding[deviceInfo] == 0 {
                deviceSettings[index] = newSetting
                delegate.reloadDeviceViewAtIndex(index)
            } else {
                // Just update the retrieval time:
                deviceSettings[index] = DeviceSetting(device: deviceInfo, setting: oldSetting, retrieved: lastTimeADeviceWasSeen)
            }
        } else {
            deviceSettings.append(newSetting)
            delegate.insertDeviceViewAtIndex(deviceSettings.count - 1)
        }
        
        removeErrorFor(deviceInfo, forOperation: .FetchSetting)
        updateErrorText()
    }
    
    func removeErrorFor(device: DeviceInfo, forOperation operation: Operation) {
        if let i = errors.indexOf({ $0.device == device && $0.cause == operation }) {
            // We previously had an error with this device when performing this operation, but it has succeeded now so whatever was causing the error is presumably now fixed.
            errors.removeAtIndex(i)
        }
    }
    
    func newFetchError(deviceInfo: DeviceInfo, error: AppError) {
        newOperationError(deviceInfo, error: error, operation: .FetchSetting)
        
        // We haven't fetched the setting successfully and any previous setting we fetched might be out of date so remove it to avoid confusing users with possibly incorrect information:
        removeSettingFor(deviceInfo)
    }
    
    func newOperationError(deviceInfo: DeviceInfo, error: AppError, operation: Operation) {
        lastTimeADeviceWasSeen = awakeUptime()
        let newError = Error(device: deviceInfo, error: error, cause: operation)
        
        if let index = (errors.indexOf { $0.device == deviceInfo }) {
            // We already have an error for this device.
            errors[index] = newError
        } else {
            errors.append(newError)
        }
        updateErrorText()
    }
    
    func updateErrorText() {
        delegate.updateErrorText({
            if self.errors.count > 0 {
                return (self.errors.map { describeError($0.error, forDevice: $0.device) }).joinWithSeparator("\n\n") + "\n\n\(errorContactInstruction())"
            } else {
                if weHaventSeenADeviceInAWhile() {
                    return noDevicesContactInstruction()
                } else {
                    return ""
                }
            }
            }())
    }
    
    func weHaventSeenADeviceInAWhile() -> Bool {
        return deviceSettings.isEmpty && errors.isEmpty && (awakeUptime() - lastTimeADeviceWasSeen) >= 5
    }
    
    func removeSettingFor(device: DeviceInfo) {
        if let i = deviceSettings.indexOf( { $0.device == device } ) {
            deviceSettings.removeAtIndex(i)
            delegate.deleteDeviceViewAtIndex(i)
        }
    }
    
    func removeOldResults() {
        let now = awakeUptime()
        let oldestAllowedTime = now - 5
        
        func isCurrent(setting: DeviceSetting) -> Bool { return setting.retrieved >= oldestAllowedTime }
        
        if !deviceSettings.all(isCurrent) {
            var newSettings = [DeviceSetting]()
            var rowIndicesToDelete = [Int]()
            for (index, setting) in deviceSettings.enumerate() {
                if isCurrent(setting) {
                    newSettings.append(setting)
                } else {
                    rowIndicesToDelete.append(index)
                }
            }
            
            assert(rowIndicesToDelete.count > 0)
            
            deviceSettings = newSettings
            
            delegate.deleteDeviceViewsAtIndices(rowIndicesToDelete)
        }
        
        if weHaventSeenADeviceInAWhile() { updateErrorText() }
    }
    
}

protocol ModelViewDelegate {
    
    // FIXME re-order these
    func reloadDeviceViewAtIndex(index: Int)
    func insertDeviceViewAtIndex(index: Int)
    func updateErrorText(text: String)
    func deleteDeviceViewAtIndex(index: Int)
    func deleteDeviceViewsAtIndices(indices: [Int])
    
}
