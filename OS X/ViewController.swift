import Cocoa

class ViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    override func viewDidLoad() {
        // FIXME remove test device:
        deviceSettings.append(DeviceSetting(device: DeviceInfo(name: "Test Device", baseURL: NSURL(string: "http://127.0.0.1:8080")!), setting: true, retrieved: awakeUptime()))
    }
    
    // Only touch these from the main thread:
    var deviceSettings = [DeviceSetting]()
    
    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        return deviceSettings.count
    }
    
    func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
//        let deviceSetting = deviceSettings[row]
        let columnID = tableColumn!.identifier
        
        let view = tableView.makeViewWithIdentifier(columnID, owner: self)
        
        // FIXME populate view
        
        return view
    }
    
    func selectionShouldChangeInTableView(tableView: NSTableView) -> Bool {
        return false
    }
    
}
