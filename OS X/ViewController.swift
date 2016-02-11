import Cocoa

class ViewController: NSViewController, ModelViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    
    var model: UIModel!
    
    @IBOutlet weak var deviceTable: NSTableView!
    @IBOutlet weak var errorLabel: NSTextField!
    @IBOutlet var errorLabelConstraint: NSLayoutConstraint!
    
    var allColumns: NSIndexSet!
    let rowAnimationOptions = NSTableViewAnimationOptions.SlideDown
    
    override func viewDidLoad() {
        model = UIModel(delegate: self)
        allColumns = NSIndexSet(indexesInRange: NSRange(0..<deviceTable.numberOfColumns))
        updateErrorText("")
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
        deviceTable.insertRowsAtIndexes(row(index), withAnimation: rowAnimationOptions)
    }
    
    func row(index: Int) -> NSIndexSet { return NSIndexSet(index: index) }
    
    func reloadDeviceViewAtIndex(index: Int) {
        deviceTable.reloadDataForRowIndexes(row(index), columnIndexes: allColumns)
    }
    
    func deleteDeviceViewAtIndex(index: Int) {
        deviceTable.removeRowsAtIndexes(row(index), withAnimation: rowAnimationOptions)
    }
    
    func deleteDeviceViewsAtIndices(indices: [Int]) {
        let indexSet = NSMutableIndexSet()
        for i in indices { indexSet.addIndex(i) }
        deviceTable.removeRowsAtIndexes(indexSet, withAnimation: rowAnimationOptions)
    }
    
    func updateErrorText(text: String) {
        errorLabel.stringValue = text
        
        let errorLabelShouldBeHidden = text.isEmpty
        let errorLabelIsHidden = errorLabel.hidden
        
        if errorLabelShouldBeHidden != errorLabelIsHidden {
            errorLabel.hidden = errorLabelShouldBeHidden
            errorLabelConstraint.active = !errorLabelShouldBeHidden
        }
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
    
    @IBAction func checkBoxAction(sender: NSButton) {
        let index = deviceTable.rowForView(sender)
        let (device, _) = model.deviceAndSettingAtIndex(index)
        model.toggleDevice(device, toSetting: sender.state == NSOnState)
    }

}
