import Cocoa

let args = Process.arguments
if args.count > 1 && args[1] == "-cli" {
    cli()
} else {
    NSApplication.sharedApplication().delegate = AppDelegate()
    NSApplicationMain(Process.argc, Process.unsafeArgv)
}
