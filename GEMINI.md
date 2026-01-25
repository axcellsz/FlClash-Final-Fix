# Feature Implementation: Hysteria Turbo Auto-Pilot

## 1. Objective
Integrate the standalone `auto_pilot_termux.sh` logic into the **FlClash** application to provide a seamless "Auto-Reconnect" experience using Airplane Mode toggling via Shizuku.

## 2. Background Context
- **Tooling:** Uses `rish_test` and `rish.dex` to interact with Shizuku.
- **Current Logic:** 
    1. Monitor internet connectivity using HTTP 204/200 checks (target: `http://connectivitycheck.gstatic.com/generate_204`).
    2. If connectivity fails (Timeout > 5s), trigger Airplane Mode ON, wait 3s, then Airplane Mode OFF.
    3. Wait for signal restoration (10s) before resuming monitoring.

## 3. Implementation Steps

### A. UI Integration
- Add a new toggle switch in the **Hysteria Turbo Settings** view: `"Enable Auto-Pilot (Airplane Mode Reset)"`.
- Add a description: `"Automatically resets network via Airplane Mode if connection times out."`

### B. Logic Implementation (Flutter/Dart)
- Create an `AutoPilotController` or integrate into `AppController`.
- Use a `Timer.periodic` (default 10-15s) to perform the `check_internet` task using the `dio` or `http` package.
- If the check fails:
    - Invoke the native layer or execute the shell command via `Process.run`.
    - Example Command: `./rish_test -c "cmd connectivity airplane-mode enable"`.
    - Ensure the app has the necessary files (`rish_test`, `rish.dex`) in its internal storage or assets.

### C. Android Native Integration (Optional but Preferred)
- Instead of calling shell scripts, use **MethodChannel** to trigger the Airplane Mode toggle from Kotlin.
- Integrate the Shizuku API directly into `VpnService.kt` or `MainActivity.kt` to send the `connectivity` commands.

## 4. Critical Considerations
- **Loop Prevention:** Ensure the reset logic does not trigger while the app is already in the middle of a connection attempt.
- **Permission Check:** Before starting Auto-Pilot, verify if Shizuku is running and authorized for `com.follow.clash`.
- **User Feedback:** Show a notification or log message when the app performs an automatic network reset.

## 5. Files to Reference
- `FlClash/auto_pilot_termux.sh`: Original shell logic.
- `FlClash/rish_test`: Shizuku shell wrapper.
- `FlClash/lib/views/hysteria_settings.dart`: Target for UI integration.