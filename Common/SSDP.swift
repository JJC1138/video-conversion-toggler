import Foundation

import CocoaAsyncSocket

// This is based on a lovely tiny SSDP implementation in Python that is copyright 2014 Dan Krause:
// https://gist.github.com/dankrause/6000248
// and licensed under the Apache License, Version 2.0:
// http://www.apache.org/licenses/LICENSE-2.0

public func discoverSSDPDevices(serviceType serviceType: String) {
    class Delegate: GCDAsyncUdpSocketDelegate {
        @objc func udpSocket(sock: GCDAsyncUdpSocket!, didReceiveData data: NSData!, fromAddress address: NSData!, withFilterContext filterContext: AnyObject!) {
            let responseMessage = CFHTTPMessageCreateEmpty(nil, false).takeRetainedValue()
            guard CFHTTPMessageAppendBytes(responseMessage, UnsafePointer(data.bytes), data.length) else { return }
            guard CFHTTPMessageIsHeaderComplete(responseMessage) else { return }
            guard let originalHeaders = CFHTTPMessageCopyAllHeaderFields(responseMessage)?.takeRetainedValue() as Dictionary? else { return }
            var headers = [String: String]()
            for (k, v) in originalHeaders { headers[(k as! String).uppercaseString] = (v as! String) }
            guard headers["LOCATION"] != nil && headers["ST"] != nil && headers["USN"] != nil else { return }
            
            // FIXME Do something useful with headers. Maybe populate a struct with the required parts and an 'extraHeaders' dictionary.
            print(headers["LOCATION"]) // FIXME remove
        }
    }
    
    let delegate = Delegate() // We have to keep a reference to this so it can't be inlined in the call below.
    let sock = GCDAsyncUdpSocket(delegate: delegate, delegateQueue: dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT))
    
    let maximumResponseWaitingTimeSeconds = 1
    let ip = "239.255.255.250"
    let port: UInt16 = 1900
    
    // We can't use CFHTTPMessageCreateRequest(_:_:_:_:) to create this request because M-SEARCH isn't a real HTTP/1.1 method and that function says it only accepts those methods specified by the chosen HTTP version:
    let searchMessage = [
        "M-SEARCH * HTTP/1.1",
        "HOST: \(ip):\(port)",
        "MAN: \"ssdp:discover\"",
        "ST: \(serviceType)",
        "MX: \(maximumResponseWaitingTimeSeconds)",
        "",
        "",
        ].joinWithSeparator("\r\n").dataUsingEncoding(NSUTF8StringEncoding)
    
    sock.sendData(searchMessage, toHost: ip, port: port, withTimeout: -1, tag: 0)
    try! sock.beginReceiving()
    
    sleep(UInt32(maximumResponseWaitingTimeSeconds * 2))
}
