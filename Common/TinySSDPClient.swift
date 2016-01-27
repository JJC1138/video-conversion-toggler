import Foundation

import CocoaAsyncSocket

// This is based on a lovely tiny SSDP implementation in Python that is copyright 2014 Dan Krause:
// https://gist.github.com/dankrause/6000248
// and licensed under the Apache License, Version 2.0:
// http://www.apache.org/licenses/LICENSE-2.0

public struct SSDPResponse: CustomStringConvertible, Hashable {
    public let location: NSURL
    public let st: String
    public let usn: String
    public let extraHeaders: [String: String]
    public var description: String {
        return "\(location) \(st) \(usn)"
    }
    public var hashValue: Int {
        return description.hashValue
    }
}
public func == (lhs: SSDPResponse, rhs: SSDPResponse) -> Bool {
    return
        lhs.location == rhs.location &&
        lhs.st == rhs.st &&
        lhs.usn == rhs.usn &&
        lhs.extraHeaders == rhs.extraHeaders
}

public func discoverSSDPServices(type serviceType: String = "ssdp:all", delegateQueue: dispatch_queue_t = dispatch_get_main_queue(), delegate: SSDPResponse -> Void) {
    class SocketDelegate: GCDAsyncUdpSocketDelegate {
        
        let responseDelegate: SSDPResponse -> Void
        let responseDelegateQueue: dispatch_queue_t
        var responses = Set<SSDPResponse>()
        
        init(responseDelegateQueue: dispatch_queue_t, responseDelegate: SSDPResponse -> Void) {
            self.responseDelegateQueue = responseDelegateQueue
            self.responseDelegate = responseDelegate
        }
        
        @objc func udpSocket(sock: GCDAsyncUdpSocket!, didReceiveData data: NSData!, fromAddress address: NSData!, withFilterContext filterContext: AnyObject!) {
            let responseMessage = CFHTTPMessageCreateEmpty(nil, false).takeRetainedValue()
            guard CFHTTPMessageAppendBytes(responseMessage, UnsafePointer(data.bytes), data.length) else { return }
            guard CFHTTPMessageIsHeaderComplete(responseMessage) else { return }
            guard let originalHeaders = CFHTTPMessageCopyAllHeaderFields(responseMessage)?.takeRetainedValue() as Dictionary? else { return }
            var headers = [String: String]()
            for (k, v) in originalHeaders { headers[(k as! String).uppercaseString] = (v as! String) }
            
            guard let location: NSURL = {
                guard let s = headers.removeValueForKey("LOCATION") else { return nil }
                return NSURL(string: s)
            }() else { return }
            guard let st = headers.removeValueForKey("ST") else { return }
            guard let usn = headers.removeValueForKey("USN") else { return }
            
            let response = SSDPResponse(location: location, st: st, usn: usn, extraHeaders: headers)
            // Services often respond more than once to a single request so skip duplicates:
            guard !responses.contains(response) else { return }
            
            responses.insert(response)
            dispatch_async(responseDelegateQueue) { self.responseDelegate(response) }
        }
        
    }
    
    let socketDelegate = SocketDelegate(responseDelegateQueue: delegateQueue, responseDelegate: delegate) // We have to keep a reference to this so it can't be inlined in the call below.
    let sock = GCDAsyncUdpSocket(delegate: socketDelegate, delegateQueue: dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL)) // The queue has to be serial so that duplicate filtering works.
    
    let maximumResponseWaitingTimeSeconds = 1
    let ip = "239.255.255.250"
    let port: UInt16 = 1900
    
    // We can't use CFHTTPMessageCreateRequest(_:_:_:_:) to create this request because M-SEARCH isn't a real HTTP/1.1 method and that function says it only accepts those methods specified by the chosen HTTP version:
    let searchMessage = [
        "M-SEARCH * HTTP/1.1",
        "HOST: \(ip):\(port)",
        "MAN: \"ssdp:discover\"",
        "MX: \(maximumResponseWaitingTimeSeconds)",
        "ST: \(serviceType)",
        "",
        "",
        ].joinWithSeparator("\r\n").dataUsingEncoding(NSUTF8StringEncoding)
    
    sock.sendData(searchMessage, toHost: ip, port: port, withTimeout: -1, tag: 0)
    try! sock.beginReceiving()
    
    sleep(UInt32(maximumResponseWaitingTimeSeconds * 2))
}
