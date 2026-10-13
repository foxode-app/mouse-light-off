# Mouse Light Off — Logitech lighting protocol

This implementation sends HID++ 2.0 requests using Apple's `IOHIDDevice` API. It uses the device's existing HID driver and opens the vendor command interface without exclusive access. Protocol facts were checked against the following primary implementations and documentation; no OpenRGB binary or code is bundled.

- [OpenRGB G403 detection](https://github.com/CalcProgrammer1/OpenRGB/blob/eb866970323a7bc73d68f10a68e60fd27518a221/Controllers/LogitechController/LogitechControllerDetect.cpp): USB `046d:c08f`, wired device address `ff`, legacy two-zone controller.
- [OpenRGB lighting controller](https://github.com/CalcProgrammer1/OpenRGB/blob/eb866970323a7bc73d68f10a68e60fd27518a221/Controllers/LogitechController/LogitechGLightsyncController/LogitechGLightsyncController.cpp): lighting packets, software control, off/static modes.
- [Logitech IRoot protocol](https://github.com/Logitech/cpg-docs/blob/f9107a4e3190d798f9be8c5d596f255f5e5741d2/hidpp20/features/0x0000-IRoot.rst): dynamic feature discovery.
- [libratbag HID++ implementation](https://github.com/libratbag/libratbag/blob/8235b5bb6032dea15901ab58a8218956f4494d08/src/hidpp20.c): color effects and persistence field.
- [libratbag onboard layout](https://github.com/libratbag/libratbag/blob/8235b5bb6032dea15901ab58a8218956f4494d08/src/hidpp20.c#L1816-L1842), [sector CRC](https://github.com/libratbag/libratbag/blob/8235b5bb6032dea15901ab58a8218956f4494d08/src/hidpp20.c#L1920-L1933), [directory handling](https://github.com/libratbag/libratbag/blob/8235b5bb6032dea15901ab58a8218956f4494d08/src/hidpp20.c#L2780-L2860), and [CRC initialization](https://github.com/libratbag/libratbag/blob/8235b5bb6032dea15901ab58a8218956f4494d08/src/hidpp-generic.c#L380-L403): profile format and checksum facts used for the independent raw-byte patch.
- [libratbag feature selection](https://github.com/libratbag/libratbag/blob/8235b5bb6032dea15901ab58a8218956f4494d08/src/driver-hidpp20.c#L698-L736) and [post-save DPI handling](https://github.com/libratbag/libratbag/blob/8235b5bb6032dea15901ab58a8218956f4494d08/src/driver-hidpp20.c#L1531-L1550): onboard-profile support and the need to account for a runtime DPI reset.
- [G403HID profile layout](https://github.com/clovervidia/G403HID/blob/3da4a6c6e84a4fe1a957f444bee08e7bfabf5006/G403HID/Profile.cs#L69-L77) and [device save sequence](https://github.com/clovervidia/G403HID/blob/3da4a6c6e84a4fe1a957f444bee08e7bfabf5006/G403HID/Device.cs#L334-L374): corroboration of the two LED offsets and a profile write/readback sequence. The following tail bytes remain uninterpreted here.

## Reference provenance

The links above pin the upstream revisions reviewed on 2026-10-13. OpenRGB's two referenced files identify their license as `GPL-2.0-or-later`; the lighting controller credits TheRogueZeta. The referenced libratbag sources carry the MIT license, including credits to Benjamin Tissoires and Red Hat, Inc. No license was identified for the referenced G403HID revision; only protocol facts were consulted and no code was copied or adapted from it. These upstream works are not relicensed by this project. Logitech's IRoot document is linked as the protocol source, not reproduced here.

Mouse Light Off contains its own Swift packet construction, capability discovery, reply validation, and macOS IOKit transport. The references informed USB identifiers, feature/function numbers, packet field meanings, and hardware compatibility. No upstream source files, documentation text, libraries, or executables are included in this repository or linked into the app. Preserve these references when changing protocol support; review the relevant upstream license before importing or adapting any third-party source.

## Temporary lighting: eight-model allowlist

1. Match VID `046d` and the explicit eight-model PID allowlist in `SupportedMouse.swift`, USB transport, and output report size >=20. Deduplicate HID interfaces by parent USB device registry ID (location ID fallback). A composite keyboard primary collection is valid: the tested G403 uses usage page1 / usage6.
2. Open with `kIOHIDOptionsTypeNone` (nonexclusive).
3. Query root feature `0000`, function0, payload `80 70 00`. Use the returned index for the `8070` color effects feature, not a hardcoded firmware index.
4. Query feature `8070` function0 for 1–8 zones. Query function1 for the effect count (bounded to16) and function2 for effect IDs. Resolve Disabled0 and Static1 to their actual effect indices; do not assume indices match IDs. Complete every zone’s capability discovery before writing.
5. Request software LED control with function8, payload `01 01 00`.
6. Set each discovered zone with function3 and a 16-byte payload. Off uses its discovered Disabled effect index. White uses its discovered Static effect index, RGB `ff ff ff`, static parameter2. Payload index12 (nonvolatile persistence) stays0. These temporary operations never issue onboard-profile commands.
7. Wait for an acknowledgement of each request, using the device address, feature index, function, and software tag. Device errors and timeouts produce failures.

Short report `10` is 7 bytes; long report `11` is20 bytes. Both include their report ID. Input callbacks discard unrelated mouse and keyboard reports.

Temporary off/white does not restore original LED effects on exit or persist across a power cycle. Optional auto-off reapplies these volatile settings after USB attachment or wake. The automatic recovery coordinator can repeat RAM-only off up to five times; it never schedules an onboard save or restore. Packet tests do not replace checking the physical lights after granting Input Monitoring permission.

Multiple connected supported mice are processed individually. An error on one mouse does not hide successful or failed results on others. Unsupported devices and receivers are not opened. If discovery fails, no lighting writes are sent to that device. Once mutation starts, a failure does not retry a different interface.

## Persistent lighting: G403 HERO only

Version 0.3.0 adds a separate, explicit save/restore operation for USB `046d:c08f`. Exactly one G403 HERO must be connected and its lighting discovery must report two zones. The other seven allowlisted models retain temporary lighting only. No persistence support is inferred from a similar model name or a shared lighting feature.

The tested G403 HERO reported zero persistence capability for both `0x8070` zones. Its stored LED effects were both cycle mode (`03`). Setting the persistence byte of a normal `0x8070` function3 request therefore is not the implemented solution. The app uses the existing onboard-profile feature `0x8100` and edits the validated raw profile instead.

### Accepted layout and byte changes

The feature index is discovered through IRoot. `0x8100` function0 must report memory type1, profile format2, macro format1, one profile, one out-of-box profile, 1–16 buttons, at least two sectors, and 256-byte sectors. Function2 must report onboard mode1 and function4 current sector1. The user directory at sector0 must identify the single enabled profile at sector1 followed by the directory terminator. Both complete 256-byte sectors must have valid CRCs. Unsupported layouts, host mode, unexpected directory entries, malformed replies, and checksum failures are rejected before writing.

| Profile byte offsets (half-open) | Treatment |
|---|---|
| `0..<208` | Preserve verbatim, including DPI, bindings, and profile metadata |
| `208..<219` | First 11-byte LED record; replace with zeros when its effect is enabled |
| `219..<230` | Second 11-byte LED record; replace with zeros when its effect is enabled |
| `230..<254` | Preserve verbatim; these bytes are not interpreted for G403 HERO |
| `254..<256` | Recalculate CRC and store in big-endian order |

An already-disabled LED record retains its unused parameters; a profile with no required changes receives no flash writes and does not replace the restoration baseline. CRC is CRC-16/CCITT-FALSE over bytes `0..<254`, with polynomial `0x1021`, initial value `0xffff`, no reflection, and no final XOR.

The active DPI index is read through `0x8100` function11 and the current/default DPI through feature `0x2201`. The current DPI must match the existing profile table entry for that index before saving. After saving, these runtime values are read again. If firmware changed them, the app restores the previous DPI index with `0x8100` function12 and checks the values again. It does not rewrite the DPI table or switch onboard mode or profile.

### Save transaction and backup

1. Acquire a nonblocking `flock` under the current user's backup root. All app/CLI onboard writers share this lock, including mice without a stable serial number. This lock does not coordinate unrelated vendor applications.
2. Read and validate the descriptor, mode, directory, profile, and current DPI. Plan a raw-byte patch confined to the two LED records and CRC.
3. Read the complete state again and require equality with the planned original. If the planned bytes already match, skip backup and flash writes.
4. Atomically write and synchronize a private backup, read the saved file back, and require exact equality. Read the mouse again after the backup and reject any intervening change.
5. Start a single-sector transaction with `0x8100` function6, payload `00 01 00 00 01 00`: sector1, offset0, count256. Function7 sends sixteen 16-byte chunks; function8 ends the transaction. Check each acknowledgement. Do not write the directory, ROM, profile selection, or onboard mode.
6. Read the entire descriptor, mode, directory, and profile again. The profile must equal the planned 256 bytes, and the remaining state must equal its original state. Verify runtime DPI, then apply RAM off. Restoration instead releases software LED control using `0x8070` function8 with `00 00 00` so the stored lighting can take effect.

Backups live under `~/Library/Application Support/Mouse Light Off/Backups/<identity-sha256>/`. Directories are created with mode `0700`, JSON records with mode `0600`. Each record retains the raw descriptor, directory, profile, mode/sector, schema, PID, and device identity. Per-operation history is retained alongside `g403-hero-before-off.json`, the baseline for restoring the pre-off lighting. A restore makes its own history backup without replacing that baseline. Backups and lock files are local runtime data and must not be included in source control or release artifacts.

Device identity uses a nonempty, nonzero USB serial number when available. Otherwise it uses the current boot-session UUID and physical USB attachment identity. The fallback deliberately refuses restoration after a different attachment or Mac reboot; matching the model/PID alone is insufficient. Directory names are hashed, but backup records themselves contain the identity and raw device settings and should not be attached to public bug reports without review.

### Cancellation, failure, and restoration

Save and restore are manual one-shot operations. A queued request may be cancelled before it starts. Once the profile transaction starts, it must finish the write and verification without cancellation between chunks. The app disables conflicting manual commands and the automatic-off setting while an onboard operation runs, and a normal quit request uses `terminateLater` until completion. A temporary idle-system-sleep assertion covers the transaction; it is released afterwards and does not change macOS sleep settings. These measures cannot prevent device disconnection, process termination by force, or power failure.

A write-stage error or readback mismatch is reported as an unknown outcome. There is no automatic retry, fallback interface, or automatic rollback. The app retains the backup and reports its location. Ordinary restore first requires a valid current profile; it intentionally refuses a profile whose CRC is invalid after an interrupted flash. Retaining the backup does not imply automatic repair of a corrupted sector.

Restore additionally requires the same device identity, descriptor, onboard mode, sector, directory, and every non-lighting/non-CRC profile byte as the backup. Only bytes `208..<230` are copied from the backup and the CRC is recomputed. This prevents restoration from overwriting later DPI, button, metadata, or unknown-byte changes. A subsequent automatic recovery event still applies RAM off if the user has left automatic-off enabled.

### Public entry points

| Controller API | CLI | Effect |
|---|---|---|
| `inspectOnboardLighting()` | `--inspect-onboard` | Read and validate the supported onboard layout; report stored lighting state |
| `saveOnboardOff(shouldContinue:)` | `--save-onboard-off` | Back up, save off once, verify full readback and DPI, apply RAM off |
| `restoreOnboardLighting(shouldContinue:)` | `--restore-onboard-lighting` | Restore only the same device's saved LED records and verify |

All three APIs throw on unsupported devices or failed validation and return a user-facing status string on success. The optional `shouldContinue` closure on save/restore is checked before writing, never midway through the sector transaction.

## Validation status

The user confirmed G403 HERO manual off with the dedicated prototype and generalized 0.2.1 app, and confirmed reapplication after an actual idle period and unlock with 0.2.2. That recovery did not prevent lighting during the idle period, which motivated the explicit onboard operation.

For 0.3.0, a real G403 HERO accepted the save. An independent full readback found both 11-byte LED records zeroed, valid CRC, an unchanged directory, and all non-lighting bytes preserved, including `230..<254`. The only changed offsets were 208, 214, 215, 219, 225, 226, 254, and 255. Runtime DPI remained 400 at index 0. Software LED control was also released with `0x8070` function 8, payload `00 00 00`, leaving the stored onboard lighting in control. Actual lighting throughout a subsequent idle/sleep period has not yet been verified. The other seven models and macOS 13 hardware remain unverified.

The 71 automated tests cover temporary capability discovery, recovery/cancellation, byte-preserving profile patches, CRC/layout rejection, backups, concurrent writer rejection, fresh comparisons, complete readback, unknown outcomes without retry, restricted restoration, DPI checks, and protected one-shot scheduling. These checks establish command behavior and data preservation, not the physical mouse's behavior throughout sleep.
