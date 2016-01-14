import Foundation

import CocoaAsyncSocket

// This is based on a lovely tiny SSDP implementation in Python that is copyright 2014 Dan Krause:
// https://gist.github.com/dankrause/6000248
// and licensed under the Apache License, Version 2.0:
// http://www.apache.org/licenses/LICENSE-2.0

class DiscoverSSDPDevices: NSOperation {
    
    let serviceType: String
    let runForSeconds: Int
    
    init(serviceType: String, runForSeconds: Int) {
        self.serviceType = serviceType
        self.runForSeconds = runForSeconds
    }
    
    override func main() {
        let ip = "239.255.255.250"
        let port: UInt16 = 1900
        let message = [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(ip):\(port)",
            "MAN: \"ssdp:discover\"",
            "ST: \(serviceType)",
            "MX: 3",
            "",
            "",
            ].joinWithSeparator("\r\n").dataUsingEncoding(NSUTF8StringEncoding)
        
        class Delegate: GCDAsyncUdpSocketDelegate {
            @objc func udpSocket(sock: GCDAsyncUdpSocket!, didReceiveData data: NSData!, fromAddress address: NSData!, withFilterContext filterContext: AnyObject!) {
                print("received packet") // FIXME remove
                // FIXME implement
            }
        }
        
        let delegate = Delegate()
        let sock = GCDAsyncUdpSocket(delegate: delegate, delegateQueue: dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT))
        
        sock.sendData(message, toHost: ip, port: port, withTimeout: -1, tag: 0)
        try! sock.beginReceiving()
        
        sleep(UInt32(runForSeconds))
    }
    
}
