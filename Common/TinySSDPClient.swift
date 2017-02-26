import Foundation

import CocoaAsyncSocket

// This is based on a lovely tiny SSDP implementation in Python that is copyright 2014 Dan Krause:
// https://gist.github.com/dankrause/6000248
// and licensed under the Apache License, Version 2.0:
// http://www.apache.org/licenses/LICENSE-2.0

public struct SSDPResponse: CustomStringConvertible, Hashable {
    public let location: URL
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

public func discoverSSDPServices(type serviceType: String = "ssdp:all", delegateQueue: OperationQueue = OperationQueue.main, delegate: @escaping (SSDPResponse) -> Void) {
    class SocketDelegate: NSObject, GCDAsyncUdpSocketDelegate {
        
        let responseDelegate: (SSDPResponse) -> Void
        let responseDelegateQueue: OperationQueue
        var responses = Set<SSDPResponse>()
        
        init(responseDelegateQueue: OperationQueue, responseDelegate: @escaping (SSDPResponse) -> Void) {
            self.responseDelegateQueue = responseDelegateQueue
            self.responseDelegate = responseDelegate
        }
        
        @objc func udpSocket(_: GCDAsyncUdpSocket, didReceive data: Data, fromAddress _: Data, withFilterContext _: Any?) {
            let responseMessage = CFHTTPMessageCreateEmpty(nil, false).takeRetainedValue()
            data.withUnsafeBytes() { (bytes: UnsafePointer<UInt8>) -> () in
                CFHTTPMessageAppendBytes(responseMessage, bytes, data.count)
            }
            guard CFHTTPMessageIsHeaderComplete(responseMessage) else { return }
            guard let originalHeaders = CFHTTPMessageCopyAllHeaderFields(responseMessage)?.takeRetainedValue() as Dictionary? else { return }
            var headers = [String: String]()
            for (k, v) in originalHeaders { headers[(k as! String).uppercased()] = (v as! String) }
            
            guard let location: URL = {
                guard let s = headers.removeValue(forKey: "LOCATION") else { return nil }
                return URL(string: s)
            }() else { return }
            guard let st = headers.removeValue(forKey: "ST") else { return }
            guard let usn = headers.removeValue(forKey: "USN") else { return }
            
            let response = SSDPResponse(location: location, st: st, usn: usn, extraHeaders: headers)
            // Services often respond more than once to a single request so skip duplicates:
            guard !responses.contains(response) else { return }
            
            responses.insert(response)
            responseDelegateQueue.addOperation { self.responseDelegate(response) }
        }
        
        @objc func udpSocket(_ sock: GCDAsyncUdpSocket, didSendDataWithTag tag: Int) {
            // We can't begin receiving until the socket is bound and we're doing that implicitly by sending data over it, so this is the right place for this.
            try! sock.beginReceiving()
        }
        
    }
    
    let socketDelegate = SocketDelegate(responseDelegateQueue: delegateQueue, responseDelegate: delegate) // We have to keep a reference to this so it can't be inlined in the call below.
    let sock = GCDAsyncUdpSocket(delegate: socketDelegate, delegateQueue: DispatchQueue(label: "TinySSDPClient")) // The queue has to be serial so that duplicate filtering works (and the created queue is serial by default).
    
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
        ].joined(separator: "\r\n").data(using: String.Encoding.utf8)!
    
    sock.send(searchMessage, toHost: ip, port: port, withTimeout: -1, tag: 0)
    
    sleep(UInt32(maximumResponseWaitingTimeSeconds * 2))
    
    sock.close()
}
