import Foundation

// From http://stackoverflow.com/a/25226794
class StandardErrorOutputStream: OutputStream {
    func write(_ string: String) {
        FileHandle.withStandardError.write(string.data(using: String.Encoding.utf8)!)
    }
}
var stderr = StandardErrorOutputStream()

func localString(_ key: String, fromTable table: String? = nil) -> String {
    return Bundle.main.localizedString(forKey: key, value: nil, table: table)
}

func localString(format: String, _ arguments: CVarArg...) -> String {
    // It's important to use NSLocale.currentLocale() because that gives the user's locale, whereas by default this initializer uses the system's locale.
    return String(format: format, locale: Locale.current, arguments: arguments)
}

// Based on https://developer.apple.com/library/mac/qa/qa1398/_index.html
private let machTimebaseMultiplier: TimeInterval = {
    var info = mach_timebase_info()
    mach_timebase_info(&info)
    return (TimeInterval(info.numer) / TimeInterval(info.denom)) / 1e9
}()

func awakeUptime() -> TimeInterval {
    return TimeInterval(mach_absolute_time()) * machTimebaseMultiplier
}

extension Sequence {
    func all(_ predicate: (Self.Iterator.Element) throws -> Bool) rethrows -> Bool {
        for i in self {
            if !(try predicate(i)) { return false }
        }
        return true
    }
}

public struct Counter<Element: Hashable, Counter: Integer> {
    
    fileprivate var d = [Element : Counter]()
    
    public subscript(element: Element) -> Counter {
        get {
            return d[element] as! _? ?? 0
        }
        set {
            if newValue == 0 {
                d.removeValue(forKey: element)
            } else {
                d[element] = newValue
            }
        }
    }
    
}
