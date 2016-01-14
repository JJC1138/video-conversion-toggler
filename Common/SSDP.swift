import Foundation

import CocoaAsyncSocket

// This is based on a lovely tiny SSDP implementation in Python that is copyright 2014 Dan Krause:
// https://gist.github.com/dankrause/6000248
// and licensed under the Apache License, Version 2.0:
// http://www.apache.org/licenses/LICENSE-2.0

class DiscoverSSDPDevices: NSOperation {
    
    let serviceType: String
    
    init(serviceType: String) {
        self.serviceType = serviceType
    }
    
    class Delegate: GCDAsyncUdpSocketDelegate {
        
        @objc func udpSocket(sock: GCDAsyncUdpSocket!, didReceiveData data: NSData!, fromAddress address: NSData!, withFilterContext filterContext: AnyObject!) {
            print("received packet") // FIXME remove
            // FIXME implement
        }
        
    }
    
    override func main() {
        do {
            try run()
        } catch let e {
            print(e) // FIXME remove
            // FIXME handle errors; maybe just log since this shouldn't be happening unless something unrecoverable is happening
        }
    }
    
    func run() throws {
        let queue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)
        let delegate = Delegate()
        let sock = GCDAsyncUdpSocket(delegate: delegate, delegateQueue: queue)
        
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
            ].joinWithSeparator("\r\n")
        
        sock.sendData(message.dataUsingEncoding(NSUTF8StringEncoding), toHost: ip, port: port, withTimeout: -1, tag: 0)
        try sock.beginReceiving()
        sleep(10) // FIXME remove
    }
    
}
