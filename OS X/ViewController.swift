import Cocoa

class ViewController: NSViewController, ModelViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    
    var model: UIModel!
    
    @IBOutlet weak var deviceTable: NSTableView!
    @IBOutlet weak var errorLabel: NSTextField!
    @IBOutlet var errorLabelConstraint: NSLayoutConstraint!
    
    var allColumns: IndexSet!
    let rowAnimationOptions = NSTableViewAnimationOptions.slideDown
    
    override func viewDidLoad() {
        model = UIModel(delegate: self)
        allColumns = IndexSet(integersIn: 0..<deviceTable.numberOfColumns)
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
    
    func insertDeviceViewAtIndex(_ index: Int) {
        deviceTable.insertRows(at: row(index), withAnimation: rowAnimationOptions)
    }
    
    func row(_ index: Int) -> IndexSet { return IndexSet(integer: index) }
    
    func reloadDeviceViewAtIndex(_ index: Int) {
        deviceTable.reloadData(forRowIndexes: row(index), columnIndexes: allColumns)
    }
    
    func deleteDeviceViewAtIndex(_ index: Int) {
        deviceTable.removeRows(at: row(index), withAnimation: rowAnimationOptions)
    }
    
    func deleteDeviceViewsAtIndices(_ indices: [Int]) {
        let indexSet = NSMutableIndexSet()
        for i in indices { indexSet.add(i) }
        deviceTable.removeRows(at: indexSet as IndexSet, withAnimation: rowAnimationOptions)
    }
    
    func updateErrorText(_ text: String) {
        errorLabel.stringValue = text
        
        let errorLabelShouldBeHidden = text.isEmpty
        let errorLabelIsHidden = errorLabel.isHidden
        
        if errorLabelShouldBeHidden != errorLabelIsHidden {
            errorLabel.isHidden = errorLabelShouldBeHidden
            errorLabelConstraint.isActive = !errorLabelShouldBeHidden
        }
        
        // KLUDGE This works around what seems to me to be a bug where the label only uses one line until the window is resized, at which point is dynamically wraps correctly. The workaround is imperfect because it fixes the wrapping width but since we update the error text regularly it's not a big problem.
        errorLabel.preferredMaxLayoutWidth = errorLabel.frame.size.width
    }
    
    // MARK: NSTableViewDataSource and NSTableViewDelegate
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return model.deviceCount
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let (device, setting) = model.deviceAndSettingAtIndex(row)
        let columnID = tableColumn!.identifier
        
        let view = tableView.make(withIdentifier: columnID, owner: self)
        
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
    
    func selectionShouldChange(in tableView: NSTableView) -> Bool {
        return false
    }
    
    @IBAction func checkBoxAction(_ sender: NSButton) {
        let index = deviceTable.row(for: sender)
        let (device, _) = model.deviceAndSettingAtIndex(index)
        model.toggleDevice(device, toSetting: sender.state == NSOnState)
    }

}
