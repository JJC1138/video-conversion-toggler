import Foundation

// From http://stackoverflow.com/a/24103086
func synced(lock: AnyObject, closure: () -> ()) {
    objc_sync_enter(lock)
    defer { objc_sync_exit(lock) }
    closure()
}

struct ConcurrentDictionary<Key, Value where Key: Hashable> {
    private var d = [Key: Value]()
    private var dLock = NSObject()
    subscript(k: Key) -> Value? {
        get {
            objc_sync_enter(dLock)
            defer { objc_sync_exit(dLock) }
            return d[k]
        }
        set {
            synced(dLock) {
                self.d[k] = newValue
            }
        }
    }
    func keys() -> [Key] {
        objc_sync_enter(dLock)
        defer { objc_sync_exit(dLock) }
        return [Key](d.keys)
    }
}

// From http://stackoverflow.com/a/25226794
class StandardErrorOutputStream: OutputStreamType {
    func write(string: String) {
        NSFileHandle.fileHandleWithStandardError().writeData(string.dataUsingEncoding(NSUTF8StringEncoding)!)
    }
}
var stderr = StandardErrorOutputStream()

func localString(key: String, fromTable table: String? = nil) -> String {
    return NSBundle.mainBundle().localizedStringForKey(key, value: nil, table: table)
}

func localString(format format: String, _ arguments: CVarArgType...) -> String {
    // It's important to use NSLocale.currentLocale() because that gives the user's locale, whereas by default this initializer uses the system's locale.
    return String(format: format, locale: NSLocale.currentLocale(), arguments: arguments)
}
