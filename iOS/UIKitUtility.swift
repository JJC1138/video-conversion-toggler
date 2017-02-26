import UIKit

extension UITableView {
    // Based on http://stackoverflow.com/a/19262598
    func indexPathWithSubview(_ view: UIView?) -> IndexPath? {
        var view = view
        while let v = view {
            if let tableViewCell = v as? UITableViewCell { return indexPath(for: tableViewCell) }
            view = v.superview
        }
        return nil
    }
}
