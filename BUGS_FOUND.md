# MeshCore Open — Bugs Found (Web build, manual QA)

Session: 2026-06-12 · Build served at `http://localhost:42751/` (Flutter web, debug/DDC) · Browser: Chrome

Each entry: **Severity** · where · what · repro · expected.

---

## Status
Fixes for BUG-1..4 applied on 2026-06-12 (analyze clean). **BUG-2/3 VERIFIED FIXED live:** USB device `VID:239A PID:8029` now connects on web — console shows `Open: vendorId=0x239a uartBridge=false (DTR left default)` → `Got SELF_INFO` → `connectUsb: complete`, no "device has been lost". Continuing to test the now-reachable connected screens. See "Fixes applied" at the bottom.

## Open bugs

### BUG-1 · Medium · USB connect — raw browser exception leaked to UI on picker cancel
- **Where:** "Connect over USB" screen (`usb_screen.dart`), tap **Select a USB device** → Web Serial port picker → dismiss/cancel without choosing a port.
- **What:** A red error snackbar shows the raw browser API string: `NotFoundError: Failed to execute 'requestPort' on 'Serial': No port selected by the user.`
- **Why it's a bug:** (1) Cancelling the port picker is a normal user action, not an error — it should be silent (or a neutral "No device selected" message), not a red error toast. (2) Even for real failures, leaking a raw JS `DOMException` string is poor UX. The catch handler should map known cases (user cancellation) and present friendly copy.
- **Expected:** Cancelling shows nothing or an info-level message; the UI never prints raw exception text.
- **Root cause (confirmed in source):** `usb_screen.dart:396 _friendlyErrorMessage()` maps `PlatformException`/`StateError`/etc., but the web cancel path throws a JS `DOMException` (`NotFoundError`) that matches none of the branches, so it falls through to `return error.toString();` (line 441). A friendly `l10n.usbErrorNoDeviceSelected` string already exists (line 428) but is only matched for a native `StateError` containing `'No USB serial device selected'`, not the web DOMException. Fix: detect the web no-port-selected case and route it to the existing friendly string (or suppress entirely).

### BUG-2 · HIGH · Web USB connect fails with misleading "Timed out waiting for SELF_INFO" — read-pump error is dropped by a subscription race
- **Where:** `usb_serial_service_web.dart` + `meshcore_connector.dart connectUsb()`. Repro: on web (Chrome), connect to a USB serial device (observed with `Web Serial Device VID:239A PID:8029`, an Adafruit/nRF52840 board).
- **Observed (console, happens every attempt):**
  1. Port opens OK: `USB serial opened port=Web Serial Device (VID:239A PID:8029)`
  2. **Immediately:** `_pumpReads error: NetworkError: The device has been lost.` → `_pumpReads: ended` — the read stream dies the instant it opens.
  3. Connect logic ignores that and proceeds: `requesting device info…`, writes TX frames, `ChannelSync Starting sync for 40 channels`.
  4. Nothing can ever be read back → SELF_INFO + ChannelSync retry/timeout for ~7s.
  5. Ends with `USB connection error: Bad state: Timed out waiting for SELF_INFO during connect` → disconnect. User sees a generic timeout error, not the real cause.
- **Root cause (confirmed in source):** a **subscription-timing race on a broadcast stream**:
  - `_frameController` is `StreamController<Uint8List>.broadcast()` (`usb_serial_service_web.dart:24-25`). Broadcast streams **do not buffer** — events emitted with no listener attached are silently discarded.
  - `_usbManager.connect()` starts `_pumpReads()` fire-and-forget (`usb_serial_service_web.dart:114`). On this device `_pumpReads` errors instantly and calls `_addFrameError()` (line 387/393).
  - But `connectUsb()` attaches its error listener **only after** `await Future<void>.delayed(200ms)` (`meshcore_connector.dart:1609`), then `frameStream.listen(onError: → disconnect(), onDone: → disconnect())` (lines 1610-1620). The read-pump error fired during that 200ms gap, so the `onError → disconnect` fail-fast path **never runs**.
  - With the safety net disarmed, connect falls through to `_waitForSelfInfo` (3s) + retry (3s) and throws the misleading `Timed out waiting for SELF_INFO during connect` (line 1647).
- **Expected:** A read-stream failure during connect should abort immediately with the real cause ("USB device disconnected / lost"), not a 7-second generic SELF_INFO timeout.
- **Fix directions:** attach the `frameStream` listener (or otherwise observe transport health) *before* the read pump can emit — i.e. before/at port-open, not 200ms later; OR latch the last transport error in the service and have `connectUsb` check it; OR make connect race `_waitForSelfInfo` against a transport-error future. Remove/justify the unconditional 200ms delay that opens the race window.

### BUG-3 · Likely device-level root cause for BUG-2 · DTR assertion may reset/lose nRF52840 (Adafruit, VID 0x239A) boards
- **Where:** `usb_serial_service_web.dart:285-295 _openPort()`.
- **What:** Immediately after `open()`, the code asserts `setSignals({dataTerminalReady:true, requestToSend:false})` with the comment *"Prevent ESP32 USB-CDC reset"*. That logic is tuned for ESP32. On Adafruit nRF52840 boards (VID `0x239A`, as seen here, PID `0x8029`), toggling DTR is associated with the bootloader/reset line and can cause the device to re-enumerate/reset — which plausibly produces the immediate `NetworkError: The device has been lost.` seen in BUG-2.
- **Status:** Strong hypothesis, not yet isolated (would need to test connecting with the `setSignals` call removed/varied for this board). Flagging because the device class that fails (nRF52840/Adafruit) is exactly the one where DTR semantics differ from ESP32.
- **Expected:** USB serial open should work for nRF52840-class MeshCore boards on web, or DTR handling should be conditional per device/VID.

### BUG-4 · Medium · BLE "Scan" on web (no Bluetooth adapter / unsupported) gives zero feedback
- **Where:** Scanner screen (`scanner_screen.dart`). Repro: on web with no BLE module (or any web build, since `flutter_blue_plus` doesn't support web), tap **Scan**.
- **What:** Nothing happens — no spinner, no "scanning" state, no error toast, no "Bluetooth unavailable on web" message. The button just sits there and status stays "Not connected". (Confirmed by user: "its not connecting on chrome and my computer doesn't have a ble module".)
- **Expected:** Either disable/hide BLE scan on web (the app already gates non-Chrome via `ChromeRequiredScreen`; Chrome+web still can't use `flutter_blue_plus`), or show a clear "Bluetooth isn't available in the browser — use USB or TCP" message. Silent no-op leaves the user stuck.

### BUG-5 · Low/Medium · Notifications never work until manually enabled; every incoming message logs an error
- **Where:** `notification_service.dart` — `show()` calls at lines 201/248/306/394/593 are made without ensuring notification permission was granted.
- **What (observed in console while connected):** repeated `Failed to show channel notification: Bad state: FlutterLocalNotifications.show(): You must request notifications permissions first` and the same for advert/message notifications. Each incoming channel message / advert triggers one.
- **Why:** permission is only ever requested from `app_settings_screen.dart:239` (when the user interacts with that setting). If the user never visits it, `requestPermissions()` is never called, so `show()` throws on web (and would on Android 13+ with denied permission). The errors are swallowed by `try/catch` (no crash), but notifications silently never fire and the log fills with errors.
- **Expected:** request notification permission during init / on first connect (or check `areNotificationsEnabled()` and skip `show()` when not granted) instead of calling `show()` unconditionally and relying on a caught exception per message.

### OBS-1 · RESOLVED (not a bug) · USB-on-web connection dropped after ~4 min (`device has been lost`)
- **What:** At 9:25:13 the read pump errored `NetworkError: The device has been lost.` → `USB transport error` → clean auto-disconnect back to the scanner.
- **Cause:** confirmed by user — they physically dropped/disconnected the radio. So this was a real physical disconnect, NOT a Web Serial stability issue. Positive finding: the app (with the BUG-2 fix) handled an abrupt physical disconnect cleanly and returned to the scanner.

### BUG-6 · Medium · Battery Chemistry setting permanently disabled on USB (and TCP) connections
- **Where:** App Settings → BATTERY → Battery Chemistry. `app_settings_screen.dart:610-611` gates the control on `connector.deviceId != null`; `meshcore_connector.dart` only ever assigns `_deviceId` in the **BLE** connect path (`_deviceId = device.remoteId.toString()`, line 1839, right after `_activeTransport = bluetooth`).
- **What:** When connected over USB (verified) — and by the same logic TCP — `connector.deviceId` is `null`, so the Battery Chemistry dropdown shows the subtitle "Connect to a device to choose" and is disabled, even though the device is fully connected (header shows `088EDAA0 · Connected`, radio stats live).
- **Why it matters:** USB/TCP users can never set per-device battery chemistry, so the battery percentage indicator uses the wrong voltage curve for their pack. Also user-confusing ("connect first" while connected).
- **Note:** The `088EDAA0` shown throughout the UI is a node/public-key-derived identifier, distinct from `_deviceId` (the BLE remoteId). The battery setting keys off the BLE-only `_deviceId`.
- **Fix direction:** populate a stable per-device identifier in the USB/TCP connect paths (e.g. the node public-key prefix already used for storage scoping), or key battery chemistry off that same node identity rather than the BLE remoteId.

### BUG-7 · Low/Medium · Node Name can be saved empty (no validation)
- **Where:** Settings → Node Name dialog, `settings_screen.dart:708-744 _editNodeName()`.
- **What:** Clearing the field leaves the **Save** button enabled; the handler (line 728-740) calls `connector.setNodeName(controller.text)` directly with no `trim()`/empty check. An empty or whitespace-only name can be written to the device, leaving the node nameless on the mesh (others see a blank contact). Reproduced: cleared field → "0/31", Save still active. (Did not actually save.)
- **Compare:** the Radio Settings dialog correctly disables Save on invalid input — Node Name should do the same.
- **Expected:** disable Save (or show an error) when the trimmed name is empty.

### OBS-2 · Watch · Auto-reconnect to cached Web Serial port fails after a physical drop (stale handle)
- **What:** After physical disconnects, the app auto-retries the cached port (`web:port:1`) and fails with `NetworkError: Failed to execute 'open' on 'SerialPort': Failed to open serial port` (seen at 9:26:44, 9:34:23, 9:34:53, ~30s apart). It does eventually recover (header shows Connected again), but the cached `SerialPort` handle is often stale right after an OS-level drop.
- **Note:** the native USB service explicitly documents this class of problem and avoids caching the serial handle (`_freshSerial()` comment, `usb_serial_service_native.dart:47-50`). The web service caches the port object (`_authorizedPortsByKey`), so reopen-after-drop is more fragile. Partly environmental here (user was physically re-plugging), so logged as an observation, not a confirmed bug. Worth confirming the web reconnect path discards/re-requests the port on `open()` failure rather than retry-looping on a dead handle.

---

## Notes / non-bugs
- **Radio Settings validation works:** out-of-range frequency (`9999`) shows "Invalid frequency (300-2500 MHz)" and disables Save. Good.
- **Graceful disconnect verified:** when the USB transport drops, the app auto-navigates back to the scanner and shows "Not connected" — matches the intended "handle disconnection gracefully" behavior.
- **Channel sync starts before handshake completes:** `ChannelSync Starting sync for 40 channels` fires during connect before `SELF_INFO` is confirmed (console 9:07:54). Likely harmless given BUG-2 masks it, but worth confirming the initial-sync pipeline shouldn't wait for SELF_INFO first.
- First load on `localhost:39107` rendered a blank white page and the URL later resolved to `localhost:42751`. This appears to be a dev-server startup/port artifact (the Flutter view never mounted on the first port), not an app bug. Flagging only in case the port hop is intentional behavior worth confirming.

---

## Fixes applied (2026-06-12)

- **BUG-3 (device-lost root cause):** `usb_serial_service_web.dart _openPort()` now only asserts `setSignals(DTR=true)` for known USB-UART bridge VIDs (`_uartBridgeVendorIds`: CP210x `0x10C4`, CH340 `0x1A86`, FTDI `0x0403`, PL2303 `0x067B`). Native-USB-CDC boards (nRF52840/Adafruit `0x239A`, etc.) are left untouched, since toggling DTR re-enumerates them. Added a debug log line reporting the detected vendorId and whether DTR was asserted. (The native service already documented this exact NRF52/DTR behavior — confirms the hypothesis.)
- **BUG-2 (dropped read-pump error / misleading timeout):**
  - `usb_serial_service_web.dart _pumpReads()` now flips `_status = disconnected` and latches `_lastError` when the read loop dies unexpectedly, instead of leaving the service reporting "connected".
  - Added `lastError` getter to both web + native `UsbSerialService` and to `MeshCoreUsbManager`.
  - `meshcore_connector.dart connectUsb()` now checks `_usbManager.isConnected` right after the 200ms settle delay (before waiting on SELF_INFO) and throws a clear `USB device disconnected during connect: <cause>` using the latched error — failing in ~200ms with the real reason instead of ~7s with a generic SELF_INFO timeout.
- **BUG-1 (raw exception on picker cancel):** `usb_screen.dart` added `_isUserCancelledPortPicker()`; `_showError()` now returns silently for picker cancellation (matches the web `requestPort`/"No port selected" DOMException and the native StateError) instead of showing a red toast with raw text.
- **BUG-4 (silent BLE scan on web):** `scanner_screen.dart _toggleScan()` now short-circuits on web and shows `scanner_bluetoothWebUnsupported` ("Bluetooth isn't available in the browser. Connect over USB instead.") instead of silently no-opping. New l10n key added to `app_en.arb` and regenerated for all locales (English fallback; pending auto-translation).

## Fixes applied — round 2 (2026-06-12)

- **BUG-5 (notifications never fire / error spam):** `notification_service.dart` added `_ensureCanNotify()` — caches whether the platform can actually post notifications and is now the gate on all four `show()` entry points (message/advert/channel/batch-summary). Returns false on web (the plugin has no web backend, so `show()` always threw) and honors `areNotificationsEnabled()` on Android 13+. `requestPermissions()` now refreshes the cache so enabling from settings takes effect immediately. The `cancel()` paths still use `_ensureInitialized()` (unchanged). Net: no more per-message error spam; notifications post when actually permitted.
- **BUG-6 (battery chemistry disabled on USB/TCP):** added `MeshCoreConnector.batteryDeviceKey` — returns the BLE remoteId when present (preserves existing BLE-keyed settings) and falls back to the node public key (`selfPublicKeyHex`) on USB/TCP. Both the internal `_batteryChemistryForDevice()` and the App Settings UI (`app_settings_screen.dart`) now key off `batteryDeviceKey` instead of the BLE-only `connector.deviceId`. Battery chemistry is now selectable on USB/TCP, and the battery-% curve is correct for those connections.
- **BUG-7 (empty node name savable):** `settings_screen.dart _editNodeName()` Save button is now wrapped in a `ListenableBuilder` on the text controller and is disabled (`onPressed: null`) when the trimmed name is empty; the handler saves the trimmed value. Mirrors the Radio Settings dialog's validation behavior.

All four files analyze clean. Pending live re-verification after hot restart (BUG-5: no notification errors in console; BUG-6: Battery Chemistry enabled while on USB).

---

## Suggestions / further work (2026-06-12)

### Follow-ons directly implied by the fixes
1. **Audit other per-device features for the same BLE-only gap (BUG-6 was probably not alone).** `_deviceId` is set only in the BLE connect path; anything keyed off `connector.deviceId` or `_device?.remoteId` is silently BLE-only on USB/TCP. Grep those usages and verify each works on USB/TCP, or migrate them to `batteryDeviceKey` / `selfPublicKeyHex`.
2. **Battery-chemistry key inconsistency (tradeoff in my BUG-6 fix).** I kept BLE = remoteId and USB/TCP = public key to avoid wiping saved BLE settings. Consequence: the *same physical radio* gets two different chemistry settings depending on transport. Cleaner long-term: key everything off `selfPublicKeyHex` (the canonical per-radio identity used for all other scoped storage) with a one-time migration of existing BLE-keyed values.
3. **Web reconnect should discard a stale port handle (OBS-2).** After a physical drop, auto-reconnect retry-loops on the cached `SerialPort` with `Failed to execute 'open'` before recovering. The native service deliberately avoids caching the handle (`_freshSerial()` comment). On `open()` failure the web service should drop the cached port from `_authorizedPortsByKey` and re-request (or prompt) instead of retrying a dead handle.
4. **DTR allowlist may need expansion (caveat on my BUG-3 fix).** I now assert DTR only for known UART-bridge VIDs (CP210x/CH340/FTDI/PL2303). A future board with an unlisted bridge chip won't get DTR and could reset on open. Consider a per-board config or a user-visible "hold DTR" toggle as a fallback as more hardware is tested.
5. **On web, the notification toggles are ON but inert** (same spirit as BUG-4). Now that `_ensureCanNotify()` correctly skips web, the four NOTIFICATIONS switches in App Settings still read as enabled while doing nothing in-browser. Grey them out / annotate "not available in browser" on web. Also `requestPermissions()` still returns `true` on web (fallback `return true`), which is misleading to its callers.

### Robustness / architecture
6. **The connect handshake rides on a `broadcast()` stream + an unconditional 200ms delay** — the exact combo that caused BUG-2. My fix (status flip + liveness check) closes the connect race, but any consumer that subscribes late can still miss early frames/errors. Consider readiness signaling instead of the magic delay, and/or buffering the first frames during connect.

### UX polish observed
7. **Two "Scan" buttons on the scanner empty state** (center button + bottom-right FAB) — redundant.
8. **Verify destructive actions confirm before acting.** I intentionally did NOT trigger "Clear Chat", "Delete All Paths", "Reboot Device", or "Manage Repeater" (not my device). Worth confirming each has a confirmation dialog.
9. **Telemetry screen** had no obvious "request once" affordance — only autorefresh (interval 20 / qty 10 / Enable). A manual one-shot refresh would help.

### Coverage gaps (NOT tested this session — unverified)
- Repeater management (hub / CLI / settings / status), Line-of-Sight, Path-Trace map, Community QR scanner.
- Discovery & Neighbors screens, Map cache screen, Debug log screens.
- TCP transport (no TCP device available), USB on native (Android/desktop), on-device translation (LLM).
- Contacts search/sort/filter, channel add/reorder, GPX export.

---

## Styling observations (2026-06-12)
Caveat: only viewed **dark mode** in a **wide desktop browser** (~1298px). Light mode and narrow/mobile widths not assessed.

**The color system is good — credit where due.** `mesh_theme.dart` is a coherent, semantic palette ("high-contrast slate surfaces with sky-blue accents"): slate surface ramp (`0B1220`→`334155`), sky-blue accent (`0EA5E9`), signal-green reserved for SNR only (`22C55E`), amber warn, red alert, magenta node type, a full ink ramp, and a separate light ramp. Not a generic default-Material look. (Note: the CLAUDE.md claim that MeshPalette/MeshTheme is "not currently wired" is **stale** — `main.dart:204-205` wires `MeshTheme.light()/.dark()`.)

**Issues are layout/responsiveness, not color:**
1. **No max-width constraint on web/desktop (biggest one).** No `ConstrainedBox`/`maxWidth` in `main.dart`; the app is mobile-first and stretches edge-to-edge on a wide window — chat input spans the full ~1300px, list rows are very wide, chat bubbles hug the far edges, settings rows stretch across. Recommend a centered max-width content column (phone-like, ~480–600px) or responsive breakpoints for the web build.
2. **App-bar title alignment is inconsistent.** Main tab screens (Channels/Contacts/Map) use left-aligned titles with a device-id subtitle; detail screens use `centerTitle: true` (23 files) or `AdaptiveAppBarTitle`. Reads slightly inconsistent screen-to-screen — worth one deliberate rule.
3. **Tall-viewport chat spacing.** Bottom-anchored chat leaves a large empty area at the top on a tall window (related to #1 — no height/width framing for big viewports).
4. **Minor:** map node-detail sheet stacked over the older bottom info bar (z-order overlap); the two redundant Scan buttons are also a visual duplication; verify disabled-control contrast is legible (the pre-fix battery dropdown was quite dim).
5. **Unverified:** light theme polish (light ramp exists in the palette but wasn't viewed).

---

# Retry & Path-Selection Analysis (2026-06-12, code review vs firmware)

Static review of the ACK/retry/path-selection pipeline (`message_retry_service.dart`, `path_history_service.dart`, `timeout_prediction_service.dart`, connector wiring) cross-checked against the MeshCore C++ firmware at `/mnt/Gaming/meshcore/MeshCore`. Verified against actual firmware source, not just docs.

**What's correct (verified):**
- **ACK-hash algorithm matches the firmware exactly.** Client `computeExpectedAckHash` (`message_retry_service.dart:104-136`) = `SHA256(timestamp[4 LE] ‖ (attempt&3) ‖ text ‖ sender_pubkey[32])`, first 4 bytes as LE uint32. Firmware `BaseChatMesh.cpp:413-419` builds `temp[0..3]=timestamp`, `temp[4]=attempt&3`, `temp[5..]=text` (null *not* hashed — length passed is `5+text_len`), hashed with `self_id.pub_key`. Byte order and endianness round-trip correctly (`RESP_CODE_SENT`/`PUSH_CODE_SEND_CONFIRMED` both LE uint32, `meshcore_connector.dart:5265-5409`).
- **Retry is entirely the client's job** — firmware `sendMessage` sends once, no retry loop. Correct division of responsibility.
- **Per-contact in-flight serialization** (`_sendQueue`, `message_retry_service.dart:174-208`) is the right idea — see RETRY-1 for why it's not *sufficient*.

## Open findings

### RETRY-1 · Medium · Per-contact in-flight cap doesn't protect the firmware's *global* 8-entry ACK table
- **Where:** `message_retry_service.dart:174-183` (one in-flight message *per contact*) vs firmware `examples/companion_radio/MyMesh.h:248-250` + `MyMesh.cpp:1100-1103`.
- **What:** The firmware's `expected_ack_table` is a **single global circular buffer of 8 entries** with a global `next_ack_idx`, shared across *all* contacts. The client only guarantees ≤1 in-flight *per contact*, so messaging **9+ contacts concurrently** (e.g. several active conversations whose retries overlap, or a broadcast-style burst) puts >8 entries in flight. The firmware then overwrites the oldest slot (`next_ack_idx = (next_ack_idx+1) % 8`) with no rejection — the evicted message's ACK expectation is silently dropped.
- **Consequence:** the evicted send never produces a `PUSH_CODE_SEND_CONFIRMED`, so the client times out and retries a message the radio already sent (wasted airtime), and can mark as **failed** a message that actually delivered.
- **The code comment is misleading:** `message_retry_service.dart:173-174` says serialization exists "to avoid overflowing the firmware's 8-entry expected_ack_table" — but a per-contact cap does not bound the global table.
- **Fix:** enforce a **global** concurrent-in-flight cap (≤8, ideally ~6 for headroom) across all contacts, not just per-contact; or track `next_ack_idx` pressure and back-pressure new sends.

### RETRY-2 · Medium · Firmware's reported `est_timeout` is silently discarded
- **Where:** `meshcore_connector.dart calculateTimeout()` (4379-4408); `message_retry_service.dart:405-415`.
- **What:** `RESP_CODE_SENT` carries the device's own `est_timeout` (firmware `MyMesh.cpp:1106-1110`, computed from real `getEstAirtimeFor(...)`). It's parsed into `timeoutMs` and passed to `updateMessageFromSent` as the default `actualTimeout`. But `config.calculateTimeout` is **always** set, so the device value is immediately overwritten on every message — and when the ML model has no data, `calculateTimeout` returns `physicsMax` (line 4407), **never the device-provided value**.
- **Why it's a bug:** the docstring at `message_retry_service.dart:405` ("prefer ML prediction, then device-provided, then physics fallback") describes a tier that doesn't exist — device-provided is never used. The physics fallback re-derives the firmware's flood/direct formulas, but `_estimateAirtimeMs` falls back to a hard-coded **50 ms** when radio params (freq/bw/sf/cr) aren't yet known (`meshcore_connector.dart:4341-...`), which can diverge sharply from the device's actual airtime estimate (e.g. SF12). The device already did this math correctly with the real airtime.
- **Fix:** use the device `timeoutMs` as the fallback when ML is unavailable, and as the clamp ceiling when ML is present — it's strictly better information than a 50 ms guess.

### RETRY-3 · Medium · Premature ML timeouts can delete good routes (timeout floor too low + aggressive weight decay)
- **Where:** `meshcore_connector.dart _physicsMinTimeout` (≈4360-4375); `message_retry_service.dart:491-538`; `path_history_service.dart:131-141`.
- **What:** For direct paths the timeout floor is `airtime*(hops+1)` — it omits the firmware's base (`SEND_TIMEOUT_BASE_MILLIS=500`) and per-hop processing terms (`6*airtime+250` per hop). So an ML prediction clamps as low as that floor, well under the firmware's own `500 + (6*airtime+250)*hops`. When the timer fires before an ACK could realistically return, `_handleTimeout` records a **false failure** → `recordPathResult(success:false)` decrements `routeWeight` by 0.5. A fresh path starts at weight 1.0, so **two** false timeouts drive it to ≤0 and `removePathRecord` deletes it (`path_history_service.dart:136-140`). Net: an overly tight timeout estimator actively erodes the learned route table — the opposite of what the ML system is for.
- **Fix:** raise the direct-path min floor to include the firmware base + per-hop terms (don't let ML clamp below a physically plausible RTT); and require more evidence (e.g. a higher failure count, or a confirmed `MSG_SEND` with no ACK over multiple attempts) before deleting a route rather than after two timer fires.

### RETRY-4 · Low · `handleAckReceived` fallback computes a bogus `attemptIndex`
- **Where:** `message_retry_service.dart:613-626` (fallback branch), uses `expectedHashes.indexOf(expectedHash)` as the attempt index.
- **What:** `_expectedAckHashes[messageId]` is de-duplicated on insert (line 401), and because both firmware and client mask `attempt & 0x03`, attempts 0/4/8 (and 1/5/9, …) hash to the **same** value. So the list index is neither the real attempt number nor stable. The derived `matchedAttemptIndex` is only used to pick which attempt's `PathSelection` gets credited for the delivery — so the impact is limited to path-attribution accuracy on the fallback path (the primary `_ackHashToMessageId` mapping carries the correct snapshot). Low severity, but the value is simply wrong.
- **Fix:** store the attempt index alongside each expected hash (or just reuse the snapshot in `_ackHashToMessageId`) instead of inferring it from a list position.

### RETRY-5 · Low · ML model feeds flood as `pathLength = -1`, polluting the linear coefficient
- **Where:** `timeout_prediction_service.dart:59-98` (observation), `161-200` (training).
- **What:** Flood deliveries are recorded with `pathLength: -1` **and** `isFlood: true`, then both are fed as features into a single global OLS regressor. A linear term that sees hop counts of `-1, 0, 1, 2, 3, …` with a discontinuity at the flood case distorts the `pathLength` coefficient; the `isFlood` dummy only partially compensates (it shifts the intercept, not the slope). Direct-path timeout predictions are therefore biased by flood observations and vice-versa.
- **Fix:** train separate flood vs direct models, or set `pathLength = 0` (or a dedicated flood feature only) when `isFlood`, so the hop-count slope is learned from direct paths alone.

### RETRY-6 · Low / verify · ACK hash is computed over SMAZ-transformed text — the sent frame must use byte-identical text
- **Where:** `message_retry_service.dart:328-351` — hash uses `prepareContactOutboundText(contact, text)` (SMAZ-encoded), but `config.sendMessage(contact, message.text, …)` is handed the **raw** text; correctness depends on `_sendMessageDirect`/`buildSendTextMsgFrame` applying the *exact same* SMAZ transform downstream.
- **Why it matters:** if those two paths ever diverge, or if a message exceeds the firmware's `MAX_TEXT_LEN = 160` and gets truncated device-side, the receiver hashes different bytes than the client predicted → the ACK never matches → the message retries to `failed` even though it was delivered. This is a silent, hard-to-diagnose failure mode.
- **Fix:** compute the hash from the *same* byte buffer that is actually framed and sent (single source of truth), and add a unit test that asserts hash-over-frame-text == expected ACK hash, including a >160-byte/SMAZ case.

## Observations (heuristics, not correctness bugs)
- **Flood path attribution credits a path the send didn't use.** On a successful *flood* delivery, `_recordPathResult` (`meshcore_connector.dart:1309-1354`) boosts the weight of `contact.path` (the device's *current* path) even though the message was flooded, not routed over that path. It's a reasonable "the ACK probably came back this way" heuristic, but (a) it inflates weight on an unexercised route, and (b) it reads `contact.path` which the path-return packet triggered by this very ACK may have just mutated (hence the `unawaited(getContactByKey(...))` re-fetch — a race the code papers over). Worth documenting as a heuristic and considering attributing only when the device path is confirmed fresh.
- **`calculateDefaultTimeout` (`message_retry_service.dart:713-719`)** appears to be legacy/unused by the active retry path (which always goes through `config.calculateTimeout`). If dead, remove it to avoid confusion about which timeout logic is authoritative.

## How the system could be improved
1. **Single global in-flight budget tied to the firmware's table size.** Replace the per-contact gate with a global semaphore of N (≤8) outstanding ACKs, with a small reserve. This directly models the firmware constraint and eliminates RETRY-1.
2. **Make the device timeout authoritative, ML advisory.** Use the firmware's `est_timeout` as the baseline (it has the real airtime), and let the ML model only *widen* it when history shows this contact/path is consistently slower. Never let ML clamp below a physically plausible RTT (fixes RETRY-2 + RETRY-3).
3. **Decouple "timed out" from "route failed."** A timeout is weak evidence (could be transient congestion). Track per-path *consecutive* failures and only decay/delete a route after repeated, independent failures — or after the firmware reports a genuine send failure. Add hysteresis so one slow ACK doesn't erase a known-good route.
4. **Separate latency models per route class** (flood vs direct, and ideally per hop-count bucket), or add the airtime estimate itself as a feature so the model learns a multiplier rather than re-deriving physics. Fixes RETRY-5 and makes predictions interpretable.
5. **One source of truth for outbound bytes.** Frame the message once, compute the ACK hash from those exact bytes, and reject/queue anything that would exceed `MAX_TEXT_LEN` *before* sending (rather than discovering it via never-arriving ACKs). Fixes RETRY-6.
6. **Confidence-based path selection.** `_scorePathRecord` weights reliability 0.45 / latency 0.25 / freshness 0.1 / routeWeight 0.2 with hard-coded constants. Consider surfacing these as tunables (some already are via `appSettings`) and using a Wilson lower-bound on the success ratio instead of the current `(s+1)/(n+2)` Laplace estimate, so a 1/1 path isn't ranked above a 20/22 path purely on the smoothed mean.
7. **Bound the late-ACK grace + 15-min mapping cleanup explicitly.** `handleAckReceived` cleans `_ackHashToMessageId` older than 15 min on every ACK (`message_retry_service.dart:589-599`); combined with the 30 s post-failure grace timer and `attempt&3` hash reuse, it's worth a test that a delivered-after-failed message resolves exactly once and never double-advances the send queue.


### Possible ML issues 

  1. High: training/prediction mismatch for secondsSinceLastRx.
     _lastRxTime is reset when the ACK frame arrives, then the observation is recorded, making this feature effectively zero. Prediction measures it before
     sending.
     lib/connector/meshcore_connector.dart:3867

  3. Medium: incorrect message-size input.
     Retry prediction and training use message.text.length, not UTF-8/transformed payload bytes. Unicode and compressed messages therefore receive incorrect
     airtime inputs.
     lib/services/message_retry_service.dart:405
     lib/services/message_retry_service.dart:669

  4. Medium: stale per-contact statistics.
     Old observations are removed from the 100-item model window, but never removed from _contactStats. The global model adapts while contact averages remain
     lifetime averages.
     lib/services/timeout_prediction_service.dart:76

  5. Medium: model is underconstrained.
     Ordinary linear regression starts with only 10 samples and up to four features, without outlier rejection or validation. Physics clamping limits damage,
     but unstable predictions are still likely.

  6. Low: pending observations may not persist.
     dispose() cancels the delayed save without flushing it.
     lib/services/timeout_prediction_service.dart:216
---

# ACK & Message-Delivery Analysis (2026-06-12, code review vs firmware)

Focused pass on ACK matching and message delivery (sending + receiving), cross-checked against the MeshCore firmware at `/mnt/Gaming/meshcore/MeshCore`. Companion of the earlier "Retry & Path-Selection" section — this one is about whether messages reliably reach `delivered`/`failed` and aren't lost or double-shown.

**Verified correct (recording these to close earlier open questions):**
- **ACK-hash text consistency holds.** `prepareContactOutboundText` (SMAZ / Cyr2Lat) transforms the text, and the *same* transformed bytes are used both for the wire frame (`buildSendTextMsgFrame`, `meshcore_connector.dart:~1113`) and for the expected-ack hash (`message_retry_service.dart:328-338`). The firmware hashes the raw received text bytes (SMAZ is opaque to it), so both sides agree. This resolves the RETRY-6 "verify" concern (the >160-byte truncation guard is still worth adding).
- **Connect-time queue drain exists.** `_startPostChannelInitialQueuedMessageSync` (`meshcore_connector.dart:3835`) plus the `respCodeEndOfContacts` handler (`:3936-3941`) proactively call `syncQueuedMessages(force:true)` after the SELF_INFO→channels→contacts pipeline, so messages that arrived while disconnected are pulled on reconnect — not solely dependent on a live `PUSH_CODE_MSG_WAITING` tickle.
- **Firmware de-dups inbound packets.** `SimpleMeshTables::hasSeen` keeps a 160-entry packet-hash seen-table (`src/helpers/SimpleMeshTables.h:34-53`), so the same on-air packet arriving via multiple flood paths is dropped, not delivered twice.
- **Channel sends do reach `sent`.** `_handleOk` promotes the pending channel message on the firmware's generic OK (`meshcore_connector.dart:5370`), and the echo-heard path promotes it again (`:5990`). (So the "stuck pending on success" worry is unfounded — but see DELIVERY-1 for the error path.)

## Open findings

### DELIVERY-1 · Medium · A rejected (or lost-response) channel send is stuck "pending" forever
- **Where:** `_handleErrorFrame` (`meshcore_connector.dart:4007-4024`); `ChannelMessageStatus` has only `{pending, sent, failed}` and nothing ever sets `failed` for a channel message.
- **What:** When the firmware answers a `cmdSendChannelTxtMsg` with an error frame (e.g. `ERR_CODE_NOT_FOUND` for an unknown/unconfigured channel — firmware `MyMesh.cpp:1131-1135` writes an err frame on failure), the handler removes the message from `_pendingChannelSentQueue` (line 4023) **but never marks the message `failed`**. The same happens if the OK/ERR response is simply lost. Result: the bubble shows "pending/sending" indefinitely with no error, and there is no retry or timeout to resolve it.
- **Contrast:** direct messages have a full timeout→retry→`failed` path; channel messages have *no* failure path at all.
- **Fix:** in `_handleErrorFrame`, set the matching channel message to `failed` (mirror `_markPendingChannelMessageSentById`). Optionally add a short watchdog so a channel send with no OK/ERR within N seconds flips `pending`→`failed`.

### DELIVERY-2 · Medium · Firmware offline queue (16) silently drops *contact* messages on overflow
- **Where:** firmware `examples/companion_radio/MyMesh.cpp:219-255` (`addToOfflineQueue`), `MyMesh.h:240` (`OFFLINE_QUEUE_SIZE 16`).
- **What:** Inbound messages are buffered in a 16-slot queue and tickled to the app via `PUSH_CODE_MSG_WAITING`. On overflow the firmware evicts the oldest **channel** message to make room; if all 16 queued entries are **contact/direct** messages, the new message is **silently dropped** — no error, no notification to the app.
- **Consequence:** a burst of direct messages while the app is backgrounded/slow/disconnected can lose messages with zero indication. The client drains in a loop on tickle and on connect (good), but it cannot recover a message the firmware already discarded.
- **Fix (client side):** drain as fast as possible — the current one-at-a-time request/response loop (`_requestNextQueuedMessage`) round-trips per message; consider keeping the pump saturated. There's no app-side way to detect the drop, so also worth raising upstream (a queue-overflow counter in firmware stats would let the app warn the user).

### DELIVERY-3 · Low/Medium · Inbound contact-message de-dup can drop a *legitimate* message
- **Where:** `_handleIncomingMessage` de-dup (`meshcore_connector.dart:~4759-4772`): skips an incoming message if a message with the same `(timestampSeconds, text)` exists in the last 10 messages from that sender.
- **What:** Timestamps are second-resolution, so two genuinely distinct messages with identical text within the same second (e.g. sending "ok" twice) collide and the second is silently dropped. The firmware already de-dups true on-air duplicates at the packet-hash layer (see "verified correct"), so this app-layer heuristic is largely redundant *and* introduces a real (if uncommon) data-loss path; it also only looks back 10 messages, so a re-delivered queued message after a longer gap can slip through as a "new" duplicate.
- **Fix:** lean on the firmware's packet identity instead of `(timestamp,text)`, or narrow the heuristic (e.g. only treat as duplicate within a very short window AND when flagged as a flood repeat), so identical-text messages aren't lost.

### DELIVERY-4 · Low · ACK match is 4-byte-hash-only, no sender identity, against a *global* 8-slot table
- **Where:** firmware `processAck` (`MyMesh.cpp:411-427`) — `memcmp(data, &expected_ack_table[i].ack, 4)` over 8 slots, clears the slot to 0 on first match.
- **What:** matching uses only the first 4 hash bytes with no check that the ACK came from the intended recipient, against the same global 8-entry circular table called out in RETRY-1. So (a) >8 concurrent in-flight sends evict a slot → that message never gets `PUSH_CODE_SEND_CONFIRMED` → client retries/false-fails; (b) a ~1/2^32-per-concurrent-send chance of a cross-message false confirm. Duplicate ACKs are handled safely (slot cleared after first match; the random 6th ACK byte doesn't affect the 4-byte compare). Low severity on its own; the real lever is RETRY-1's recommended **global** in-flight cap (≤8).

### DELIVERY-5 · Info · Round-trip time is measured from queueing, not transmission
- **Where:** firmware `trip_time = getMillis() - expected_ack_table[i].msg_sent` (`MyMesh.cpp:417`), where `msg_sent` is stamped when the message is enqueued (`:1100`).
- **What:** the `tripTimeMs` the app receives (and feeds the ML timeout model) includes the firmware's TX-queue wait when the radio is busy, so observations are inflated under load. Compounds the ML-input issues already logged (RETRY-5 / the ML notes above). Not a delivery bug, but it skews timeout prediction.

### DELIVERY-6 · Low / verify · Command/CLI sends use `expected_ack = 0` — must not ride the ACK retry path
- **Where:** firmware sets `expected_ack = 0` for `TXT_TYPE_CLI_DATA` and the recipient sends no ACK (`MyMesh.cpp:1088-1110`, `BaseChatMesh.cpp:244-252`); `RESP_CODE_SENT` then carries a zero hash.
- **What:** if any client path routes a CLI/repeater command through `MessageRetryService` (which computes a *non-zero* expected hash and waits for `PUSH_CODE_SEND_CONFIRMED`), it would never match → spurious retries and a false "failed". Need to confirm the repeater-CLI/command path is separate from the text-message ACK machinery (the connector does call `_recordPathResult` for "repeater command results" — worth tracing that it isn't also arming an ACK wait).
- **Fix/verify:** ensure command sends bypass the expected-ack/retry tracking entirely, or special-case `expected_ack == 0` in `updateMessageFromSent` as "no ACK expected → mark sent, don't wait".

---

# Live Log Analysis — "JC Room Server" session (2026-06-12)

Real device log (BLE/USB, auto route rotation ON) sending to a multi-hop room server. This is a near-perfect live reproduction of RETRY-2, RETRY-3, and RETRY-5. The ACK *matching* is correct (every `RESP_CODE_SENT` matches its message); what's broken is **timeout estimation and path rotation** — the app declares failures and retries messages that are actually still in flight.

### Evidence by symptom

1. **Flood timeout = 151 seconds (RETRY-5, live).**
   `raw prediction=100638ms for pathLength=-1 → ML timeout 150959ms`. Feeding `pathLength=-1` into the linear model makes the flood case extrapolate off a cliff; the `.clamp(physicsMin, physicsMax)` didn't help because the flood `physicsMax` (`500 + 16·airtime`) was also huge. A message that falls back to flood effectively hangs for ~2.5 minutes.
   - Also seen: `raw prediction=-3467ms for pathLength=1, messageBytes=172` — a **negative** predicted time. Discarded by the `<=0` guard, but proves the OLS model is unstable/underconstrained (matches the ML notes).

2. **Premature timeouts on a working route (RETRY-3, live).**
   `"Its going well"` was **delivered in 16037ms**, but attempt 0/1 used timeouts of **14420ms / 10240ms** — shorter than the real round-trip — so they fired `Timeout → retrying` before the ACK could return. The `g:` message `delivered ... in 9418ms` arrived *after* a retry had already been scheduled. Messages that are genuinely in flight are being declared failed.

3. **Device `est_timeout` ignored (RETRY-2, live).**
   Every send gets a clean `RESP_CODE_SENT` (which carries the firmware's own `est_timeout`), but the app overrides it with the runaway ML value. The device's estimate would have been far saner than both the 10s (too short) and 151s (too long) ML outputs.

4. **Path rotation never converges.**
   Single message, per-retry path: `pathLength 3 → 2 → 1 → 2 → -1(flood)`; timeout target swings `25s → 19s → 13s → 19s → 151s`. Routes that just delivered (`g:` over 2 hops) are abandoned on the next message. On a 2-5 hop room server on a congested channel, the thrash never settles.

5. **Retries congest the channel.**
   `Radio quiet for 3037ms`, `Post-inbound backoff: waiting 14808ms` — channel is busy. Backoffs (`1/2/4/8s`) are far shorter than the 19-34s timeouts, so retries stack onto a multi-hop path and reduce delivery odds.

6. **`attempt & 3` hash reuse visible.** `"I have some really c..."` attempt 0 and attempt 4 both expect `b8bfa902`; `"JC you around?"` reuses `b2074391`. Attempts 0/4 are indistinguishable on the wire (RETRY-4 / masking).

7. **Room login runs a separate, untracked ACK path (relates to DELIVERY-6).** `No pending message found for ACK hash: b0023dab` ×5 during `[RoomLogin]` — login sends with an expected ACK that `MessageRetryService` never registered, so every login confirm logs as unmatched. Login has its own 26s timeout/retry and eventually succeeds.

### Highest-impact fix (from this log)
Fix the timeout side: **stop feeding flood as `pathLength=-1`, hard-cap the ML output (≈30-45s), and fall back to the device's `est_timeout` instead of the runaway ML value.** That alone kills the 151s hang and the premature retries. Contained to `timeout_prediction_service.dart` + `calculateTimeout` in `meshcore_connector.dart`.

---

# Design Proposal — Replace the timeout regressor; split timeout from loss (2026-06-12)

Outcome of analyzing the JC Room Server log: the OLS `LinearRegressor` in `timeout_prediction_service.dart` is the wrong tool, and it's conflating two separate questions. This sketches the replacement before any code changes.

## The core insight (why this isn't TCP, and what that implies)

This is slow, **lossy** multi-hop radio: a message can be lost on a forward hop (never reaches the recipient) or delivered-but-the-ACK-return-is-lost. Two consequences drive the whole design:

1. **On a lossy link, a longer timeout recovers nothing — only a retry does.** The timeout is your *time-to-retry*. Loss is the common outcome to a distant (5-hop) node, so inflating the timeout (e.g. the observed 151 s flood value) just maximizes idle time before the one action that helps. The right timeout is **the tightest value that still covers a realistically *successful* round-trip** (~P90–95 of success RTT), then give up and retry.
2. **The latency model is already blind to loss.** `recordObservation` is only called from `handleAckReceived` — i.e. only on success. Lost messages produce no sample. So the regressor estimates "time of a *successful* round-trip" (same data an EWMA would use), just with extrapolation/negative/explosion failure modes on top. Modeling loss for real would require censored-data/survival analysis, which is far heavier than needed.

**Conclusion:** stop using one fragile latency regressor to answer both "how long to wait" and "is this route any good." Split them.

## Part A — Timeout: physics-anchored, capped, adaptive RTT (replaces the OLS model)

Drop `ml_algo` / `ml_dataframe`. Keep the existing `predictTimeout` / `recordObservation` interface so `calculateTimeout` and the connector wiring are untouched; swap the internals.

Per **route class** = (hop count, flood-vs-direct); shared across contacts since data is sparse.

```
// baseline from physics (deterministic, generalizes to unseen hop/byte combos
// from sample #1). Use the LoRa airtime formula already in the connector, or the
// device's est_timeout from RESP_CODE_SENT (RETRY-2).
base = physicsEstimate(hops, bytes, sf, bw, cr)

// learn only a BOUNDED multiplicative overhead from real successes (congestion,
// per-hop processing). EWMA, clamped so it can never explode or go negative.
on success(sample, hops, bytes):
    ratio  = sample / physicsEstimate(hops, bytes, ...)
    f[class] = (1-α)·f[class] + α·clamp(ratio, 0.5, 4.0)     // α≈0.125
    v[class] = (1-β)·v[class] + β·|f[class] - ratio|          // β≈0.25 (deviation)

predictTimeout(hops, bytes):
    est = base · f[class]
    return clamp(est + 4·v[class]·base, physicsMin, HARD_MAX)  // HARD_MAX ≈ 30–45 s
```

Properties this fixes, by construction:
- **No 151 s / no negatives** — output is `physics × bounded factor + bounded variance`, hard-capped.
- **No flood discontinuity** — flood is its own class with its own factor, never `pathLength = -1` on a shared axis (kills RETRY-5).
- **No cold start** — seed `f=1`, `v=0`; the physics/device baseline is sensible from message #1; observations only refine the factor (removes the "need 10 samples" gate).
- **Variance is the timeout's whole point** — `est + k·deviation` is a calibrated high-percentile wait, so genuinely-in-flight messages aren't cut off early (kills RETRY-3), while staying tight enough that lost messages retry promptly.
- **Drops two dependencies**, ~15 lines, debuggable.

Also remove the dead/broken `secSinceRx` feature (recorded ≈0; see ML notes) and feed transformed/UTF-8 payload bytes, not `text.length`.

## Part B — Loss: route reliability drives retry / reroute / flood (data already exists)

The "is this path even working" question belongs to `PathHistoryService`, which already tracks `successCount` / `failureCount` / `routeWeight` per path. Treat that as a Bernoulli delivery-probability estimate (Wilson or Beta lower bound on success rate) and use it for the *decision*, not the timeout:

- **High-confidence working route** → keep using it; on a single timeout, retry the *same* path once (the ACK return may just have been lost) before changing anything.
- **Degrading route** (success rate dropping) → switch to the next-best ranked path rather than hammering a dying one.
- **No confident route / repeated failures** → flood to rediscover, then pin the rediscovered path (don't immediately rotate off it — the log shows good routes being abandoned the next message).

This replaces the current "rotate the path on every retry" churn (which made the timeout target swing 25 s→19 s→13 s→19 s→151 s and never converged) with: **pin a working route; only re-route/flood when reliability says the route is actually bad.**

## Sequencing
1. Part A first (self-contained, biggest visible win — kills the 151 s hang and premature retries; removes ml_algo). Same public interface, so low blast radius.
2. Then Part B (path-decision policy), which also subsumes much of the separate "location-change brittleness" work — a route that stops delivering after you move is just a route whose reliability dropped.
