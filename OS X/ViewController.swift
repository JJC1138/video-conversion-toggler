import Cocoa

class ViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    override func viewDidLoad() {
        // FIXME remove test devices:
        deviceSettings.append(DeviceSetting(device: DeviceInfo(name: "Test Device", baseURL: NSURL(string: "http://127.0.0.1:8080")!), setting: false, retrieved: awakeUptime()))
        deviceSettings.append(DeviceSetting(device: DeviceInfo(name: "Other Test Device", baseURL: NSURL(string: "http://127.0.0.1:8081")!), setting: true, retrieved: awakeUptime()))
    }
    
    // Only touch these from the main thread:
    var deviceSettings = [DeviceSetting]()
    
    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        return deviceSettings.count
    }
    
    func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let deviceSetting = deviceSettings[row]
        let columnID = tableColumn!.identifier
        
        let view = tableView.makeViewWithIdentifier(columnID, owner: self)
        
        if columnID == "Device" {
            let view = view as! NSTableCellView
            view.textField!.stringValue = deviceSetting.device.description
        } else if columnID == "Video Conversion" {
            let view = view as! NSButton
            view.state = deviceSetting.setting ? NSOnState : NSOffState
        } else {
            assert(false)
        }
        
        return view
    }
    
    func selectionShouldChangeInTableView(tableView: NSTableView) -> Bool {
        return false
    }
    
}
