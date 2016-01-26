import Foundation

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
