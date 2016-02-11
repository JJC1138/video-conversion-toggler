import Cocoa

class ViewController: NSViewController, ModelViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    
    var model: UIModel!
    
    override func viewDidLoad() {
        model = UIModel(delegate: self)
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        model.start()
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        model.stop()
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear()
        model.resetErrors()
    }
    
    // MARK: ModelViewDelegate
    
    func insertDeviceViewAtIndex(index: Int) {
        // FIXME implement
    }
    
    func reloadDeviceViewAtIndex(index: Int) {
        // FIXME implement
    }
    
    func deleteDeviceViewAtIndex(index: Int) {
        // FIXME implement
    }
    
    func deleteDeviceViewsAtIndices(indices: [Int]) {
        // FIXME implement
    }
    
    func updateErrorText(text: String) {
        // FIXME implement
    }
    
    // MARK: NSTableViewDataSource and NSTableViewDelegate
    
    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        return model.deviceCount
    }
    
    func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let (device, setting) = model.deviceAndSettingAtIndex(row)
        let columnID = tableColumn!.identifier
        
        let view = tableView.makeViewWithIdentifier(columnID, owner: self)
        
        if columnID == "Device" {
            let view = view as! NSTableCellView
            view.textField!.stringValue = device.description
        } else if columnID == "Video Conversion" {
            let view = view as! NSButton
            view.state = setting ? NSOnState : NSOffState
        } else {
            assert(false)
        }
        
        return view
    }
    
    func selectionShouldChangeInTableView(tableView: NSTableView) -> Bool {
        return false
    }
    
}
