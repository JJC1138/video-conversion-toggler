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
            return self.d[k]
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
        return [Key](self.d.keys)
    }
}

// From http://stackoverflow.com/a/25226794
class StandardErrorOutputStream: OutputStreamType {
    func write(string: String) {
        NSFileHandle.fileHandleWithStandardError().writeData(string.dataUsingEncoding(NSUTF8StringEncoding)!)
    }
}
var stderr = StandardErrorOutputStream()
