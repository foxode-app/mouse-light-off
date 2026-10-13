# Mouse Light Off — Logitech lighting protocol

This implementation sends HID++ 2.0 requests using Apple's `IOHIDDevice` API. It uses the device's existing HID driver and opens the vendor command interface without exclusive access. Protocol facts were checked against the following primary implementations and documentation; no OpenRGB binary or code is bundled.

- [OpenRGB G403 detection](https://github.com/CalcProgrammer1/OpenRGB/blob/eb866970323a7bc73d68f10a68e60fd27518a221/Controllers/LogitechController/LogitechControllerDetect.cpp): USB `046d:c08f`, wired device address `ff`, legacy two-zone controller.
- [OpenRGB lighting controller](https://github.com/CalcProgrammer1/OpenRGB/blob/eb866970323a7bc73d68f10a68e60fd27518a221/Controllers/LogitechController/LogitechGLightsyncController/LogitechGLightsyncController.cpp): lighting packets, software control, off/static modes.
- [Logitech IRoot protocol](https://github.com/Logitech/cpg-docs/blob/f9107a4e3190d798f9be8c5d596f255f5e5741d2/hidpp20/features/0x0000-IRoot.rst): dynamic feature discovery.
- [libratbag HID++ implementation](https://github.com/libratbag/libratbag/blob/8235b5bb6032dea15901ab58a8218956f4494d08/src/hidpp20.c): color effects and persistence field.

## Reference provenance

The links above pin the upstream revisions reviewed on 2026-10-13. OpenRGB's two referenced files identify their license as `GPL-2.0-or-later`; the lighting controller credits TheRogueZeta. The referenced libratbag file carries the MIT license and credits Benjamin Tissoires and Red Hat, Inc. These licenses belong to the upstream files and are not relicensed by this project. Logitech's IRoot document is linked as the protocol source, not reproduced here.

Mouse Light Off contains its own Swift packet construction, capability discovery, reply validation, and macOS IOKit transport. The references informed USB identifiers, feature/function numbers, packet field meanings, and hardware compatibility. No upstream source files, documentation text, libraries, or executables are included in this repository or linked into the app. Preserve these references when changing protocol support; review the relevant upstream license before importing or adapting any third-party source.

## Sequence

1. Match VID `046d` and the explicit eight-model PID allowlist in `SupportedMouse.swift`, USB transport, and output report size >=20. Deduplicate HID interfaces by parent USB device registry ID (location ID fallback). A composite keyboard primary collection is valid: the tested G403 uses usage page1 / usage6.
2. Open with `kIOHIDOptionsTypeNone` (nonexclusive).
3. Query root feature `0000`, function0, payload `80 70 00`. Use the returned index for the `8070` color effects feature, not a hardcoded firmware index.
4. Query feature `8070` function0 for 1–8 zones. Query function1 for the effect count (bounded to16) and function2 for effect IDs. Resolve Disabled0 and Static1 to their actual effect indices; do not assume indices match IDs. Complete every zone’s capability discovery before writing.
5. Request software LED control with function8, payload `01 01 00`.
6. Set each discovered zone with function3 and a 16-byte payload. Off uses its discovered Disabled effect index. White uses its discovered Static effect index, RGB `ff ff ff`, static parameter2. Payload index12 (nonvolatile persistence) stays0. No onboard-profile commands are issued.
7. Wait for an acknowledgement of each request, using the device address, feature index, function, and software tag. Device errors and timeouts produce failures.

Short report `10` is 7 bytes; long report `11` is20 bytes. Both include their report ID. Input callbacks discard unrelated mouse and keyboard reports.

The app does not restore original LED effects on exit and does not claim persistent lighting across a power cycle. Optional auto-off reapplies volatile settings after USB attachment or wake. Packet tests do not replace checking the physical lights after granting Input Monitoring permission.

Multiple connected supported mice are processed individually. An error on one mouse does not hide successful or failed results on others. Unsupported devices and receivers are not opened. If discovery fails, no lighting writes are sent to that device. Once mutation starts, a failure does not retry a different interface.

G403 HERO off was confirmed by the user with the original two-zone prototype. Generalized discovery and the other seven models are covered by protocol fixtures but remain physically unverified.
