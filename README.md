# Video Conversion Toggler for Denon and Marantz AV Receivers

Video Conversion Toggler is an app for Apple TV and other Apple platforms for toggling the video conversion setting on Denon and Marantz AV receivers. It wasn't made by Denon or Marantz and has no connection with those companies.

It exists because I found myself wanting to toggle this setting often when using Apple TV because some types of content are best with it switched off (games, apps with animation, and some video content at 50 or 59.97 Hz), and somes types are best with it switched on (films and most TV at 23.976 Hz). I made this app so that I could toggle it quickly from the Apple TV without having to use another remote and navigate through menus.

Unfortunately the setting that's needed isn't included in the official Denon/Marantz control protocol, so it's not available in remote control apps from the manufacturers or third parties. The setting is included in the devices' web interfaces, though, so this app just pretends to be a web browser and toggles it that way.

### Copyright

Copyright © 2016 Jon Colverson and available under the MIT license:

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Code includes:

* parts based on [SSDP code](https://gist.github.com/dankrause/6000248) copyright by Dan Krause and licensed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0)

Executable versions include:

* [Alamofire](https://github.com/Alamofire/Alamofire) copyright by the Alamofire Software Foundation and licensed under the [MIT license](https://raw.githubusercontent.com/Alamofire/Alamofire/master/LICENSE)
* [CocoaAsyncSocket](https://github.com/robbiehanson/CocoaAsyncSocket) by Robbie Hanson and in the public domain
* [Fuzi](https://github.com/cezheng/Fuzi) copyright by Ce Zheng and licensed under the [MIT license](https://raw.githubusercontent.com/cezheng/Fuzi/master/LICENSE)
* [HTMLReader](https://github.com/nolanw/HTMLReader) by Nolan Waite and in the public domain
