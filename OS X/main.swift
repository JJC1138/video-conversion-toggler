import Cocoa

let args = CommandLine.arguments
if args.count > 1 && args[1] == "-cli" {
    cli()
} else {
    NSApplication.shared().delegate = AppDelegate()
    NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
