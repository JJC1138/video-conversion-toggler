import UIKit

extension UITableView {
    // Based on http://stackoverflow.com/a/19262598
    func indexPathWithSubview(view: UIView?) -> NSIndexPath? {
        var view = view
        while let v = view {
            if let tableViewCell = v as? UITableViewCell { return indexPathForCell(tableViewCell) }
            view = v.superview
        }
        return nil
    }
}
