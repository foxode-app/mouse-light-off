import AppKit
import MouseLighting

let arguments = Array(CommandLine.arguments.dropFirst())
let usage =
    "Usage: MouseLightOff [--inspect | --off | --white | --inspect-onboard | --save-onboard-off | --restore-onboard-lighting | --supported | --help]"
if !arguments.isEmpty {
    guard arguments.count == 1 else {
        fputs("\(usage)\n", stderr)
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
        case "--inspect-onboard":
            print(try controller.inspectOnboardLighting())
        case "--save-onboard-off":
            print(try controller.saveOnboardOff())
        case "--restore-onboard-lighting":
            print(try controller.restoreOnboardLighting())
        case "--supported":
            for mouse in SupportedMouse.devices {
                print(
                    String(
                        format: "%@ (046d:%04x) — %@", mouse.name, mouse.productID,
                        mouse.hardwareVerified ? "旧G403版で消灯を実機確認済み" : "実機未検証"))
            }
        case "--help", "-h":
            print(usage)
            print("引数なし: 設定画面を表示。--inspect: 接続確認のみ。--off / --white: 照明を変更。")
            print("G403 HEROのみ: --inspect-onboard: 本体設定を確認。--save-onboard-off: 本体に消灯を保存。")
            print("--restore-onboard-lighting: 保存前の照明に戻す。本体の更新中はマウスを抜かないでください。")
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
    // NSApplication's delegate reference is weak; keep the menu owner alive for the run loop.
    withExtendedLifetime(delegate) {
        app.run()
    }
}
