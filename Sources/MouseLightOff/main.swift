import AppKit
import MouseLighting

let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty {
    guard arguments.count == 1 else {
        fputs("Usage: MouseLightOff [--inspect | --off | --white | --supported | --help]\n", stderr)
        exit(2)
    }
    do {
        let controller = MouseLightingController()
        switch arguments[0] {
        case "--inspect":
            print(try controller.inspect())
        case "--off":
            print(try controller.setLighting(.off))
        case "--white":
            print(try controller.setLighting(.white))
        case "--supported":
            for mouse in SupportedMouse.devices {
                print(
                    String(
                        format: "%@ (046d:%04x) — %@", mouse.name, mouse.productID,
                        mouse.hardwareVerified ? "旧G403版で消灯を実機確認済み" : "実機未検証"))
            }
        case "--help", "-h":
            print("Usage: MouseLightOff [--inspect | --off | --white | --supported | --help]")
            print("引数なし: 設定画面を表示。--inspect: 接続確認のみ。--off / --white: 照明を変更。")
        default:
            fputs("Unknown option: \(arguments[0])\n", stderr)
            exit(2)
        }
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
