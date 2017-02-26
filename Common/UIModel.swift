import Foundation

class UIModel {
    
    private let delegate: ModelViewDelegate
    
    private let oq = OperationQueue()
    private var removeOldResultsTimer: Timer?
    
    private struct DeviceSetting {
        let device: DeviceInfo
        let setting: Bool
        let retrieved: TimeInterval
    }
    
    private struct Error {
        let device: DeviceInfo
        let error: AppError
        let cause: Operation
    }
    
    private enum Operation {
        case fetchSetting
        case toggle
    }
    
    // Only touch these from the main thread:
    private var deviceSettings = [DeviceSetting]()
    private var errors = [Error]()
    private var lastTimeADeviceWasSeen = TimeInterval()
    private var toggleOperationsOutstanding = Counter<DeviceInfo, Int>()
    
    init(delegate: ModelViewDelegate) {
        self.delegate = delegate
    }
    
    func start() {
        lastTimeADeviceWasSeen = awakeUptime()
        oq.addOperation(PeriodicallyFetchAllStatuses(fetchErrorDelegate: { di, e in self.newOperationError(di, error: e, operation: .fetchSetting) } , fetchResultDelegate: self.newFetchResult))
        removeOldResultsTimer = {
            let t = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(removeOldResults), userInfo: nil, repeats: true)
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
    
    var deviceCount: Int {
        return deviceSettings.count
    }
    
    func deviceAndSettingAtIndex(_ index: Int) -> (DeviceInfo, Bool) {
        let deviceSetting = deviceSettings[index]
        return (deviceSetting.device, deviceSetting.setting)
    }
    
    func toggleDeviceAtIndex(_ index: Int) {
        let selectedDeviceSetting = deviceSettings[index]
        toggleDevice(selectedDeviceSetting.device, toSetting: !selectedDeviceSetting.setting)
    }
    
    func toggleDevice(_ deviceInfo: DeviceInfo, toSetting wantedSetting: Bool, operationWillCompleteHandler: (() -> Void)? = nil) {
        newFetchResult(deviceInfo, setting: wantedSetting) // Update the UI and such.
        
        // It's useful for the user if we clear out any errors from previous attempts now, because we're about to try again. If the old error just stayed on screen and was replaced by the same error then it would be harder to tell what had happened.
        removeErrorFor(deviceInfo, forOperation: .toggle)
        updateErrorText()
        
        toggleOperationsOutstanding[deviceInfo] += 1
        
        oq.addOperation {
            let delegateQueue = OperationQueue.main
            
            do {
                try setSetting(deviceInfo, setting: wantedSetting)
            } catch let e as AppError {
                delegateQueue.addOperation {
                    self.toggleOperationsOutstanding[deviceInfo] -= 1
                    operationWillCompleteHandler?()
                    self.newOperationError(deviceInfo, error: e, operation: .toggle)
                }
                return
            } catch { assert(false) }
            
            guard let newSetting: Bool = {
                do {
                    let newSetting = try fetchSetting(deviceInfo)
                    delegateQueue.addOperation {
                        self.toggleOperationsOutstanding[deviceInfo] -= 1
                        operationWillCompleteHandler?()
                        self.newFetchResult(deviceInfo, setting: newSetting)
                    }
                    return newSetting
                } catch let e as AppError {
                    delegateQueue.addOperation {
                        self.toggleOperationsOutstanding[deviceInfo] -= 1
                        operationWillCompleteHandler?()
                        self.newFetchError(deviceInfo, error: e)
                    }
                } catch { assert(false) }
                return nil
                }() else { return }
            
            if newSetting != wantedSetting {
                delegateQueue.addOperation { self.newOperationError(deviceInfo, error: AppError(kind: .settingDidNotChange), operation: .toggle) }
            }
        }
    }
    
    var hasAnyErrors: Bool {
        return !errors.isEmpty || weHaventSeenADeviceInAWhile()
    }
    
    func fetchAllStatusesOnce(_ operationDidCompleteHandler: @escaping (() -> Void)) {
        oq.addOperation {
            let mainQueue = OperationQueue.main
            VideoConversionToggler.fetchAllStatusesOnce(delegateQueue: mainQueue, fetchErrorDelegate: self.newFetchError, fetchResultDelegate: self.newFetchResult)
            mainQueue.addOperation(operationDidCompleteHandler)
        }
    }
    
    private func newFetchResult(_ deviceInfo: DeviceInfo, setting: Bool) {
        lastTimeADeviceWasSeen = awakeUptime()
        let newSetting = DeviceSetting(device: deviceInfo, setting: setting, retrieved: awakeUptime())
        
        if let index = (deviceSettings.index { $0.device == deviceInfo }) {
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
        
        removeErrorFor(deviceInfo, forOperation: .fetchSetting)
        updateErrorText()
    }
    
    private func removeErrorFor(_ device: DeviceInfo, forOperation operation: Operation) {
        if let i = errors.index(where: { $0.device == device && $0.cause == operation }) {
            // We previously had an error with this device when performing this operation, but it has succeeded now so whatever was causing the error is presumably now fixed.
            errors.remove(at: i)
        }
    }
    
    private func newFetchError(_ deviceInfo: DeviceInfo, error: AppError) {
        newOperationError(deviceInfo, error: error, operation: .fetchSetting)
        
        // We haven't fetched the setting successfully and any previous setting we fetched might be out of date so remove it to avoid confusing users with possibly incorrect information:
        removeSettingFor(deviceInfo)
    }
    
    private func newOperationError(_ deviceInfo: DeviceInfo, error: AppError, operation: Operation) {
        lastTimeADeviceWasSeen = awakeUptime()
        let newError = Error(device: deviceInfo, error: error, cause: operation)
        
        if let index = (errors.index { $0.device == deviceInfo }) {
            // We already have an error for this device.
            errors[index] = newError
        } else {
            errors.append(newError)
        }
        updateErrorText()
    }
    
    private func updateErrorText() {
        delegate.updateErrorText({
            if self.errors.count > 0 {
                return (self.errors.map { describeError($0.error, forDevice: $0.device) }).joined(separator: "\n\n") + "\n\n\(errorContactInstruction())"
            } else {
                if weHaventSeenADeviceInAWhile() {
                    return noDevicesContactInstruction()
                } else {
                    return ""
                }
            }
            }())
    }
    
    private func weHaventSeenADeviceInAWhile() -> Bool {
        return deviceSettings.isEmpty && errors.isEmpty && (awakeUptime() - lastTimeADeviceWasSeen) >= 5
    }
    
    private func removeSettingFor(_ device: DeviceInfo) {
        if let i = deviceSettings.index( where: { $0.device == device } ) {
            deviceSettings.remove(at: i)
            delegate.deleteDeviceViewAtIndex(i)
        }
    }
    
    @objc private func removeOldResults() {
        let now = awakeUptime()
        let oldestAllowedTime = now - 5
        
        func isCurrent(_ setting: DeviceSetting) -> Bool { return setting.retrieved >= oldestAllowedTime }
        
        if !deviceSettings.all(isCurrent) {
            var newSettings = [DeviceSetting]()
            var rowIndicesToDelete = [Int]()
            for (index, setting) in deviceSettings.enumerated() {
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
    
    func insertDeviceViewAtIndex(_ index: Int)
    func reloadDeviceViewAtIndex(_ index: Int)
    func deleteDeviceViewAtIndex(_ index: Int)
    func deleteDeviceViewsAtIndices(_ indices: [Int])
    func updateErrorText(_ text: String)
    
}
