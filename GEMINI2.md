# TASK: Integrate Advanced Auto-Pilot Dashboard & Config

## 1. Context
The basic Shizuku logic is superseded by the advanced implementation located in `lib/autopilot/`.
**Reference Files (READ THESE FIRST):**
- `lib/autopilot/auto_pilot_config_service.dart` (Persistence)
- `lib/autopilot/auto_pilot_dashboard.dart` (Main UI)
- `lib/autopilot/auto_pilot_service_configurable.dart` (Core Logic)
- `lib/autopilot/auto_pilot_settings_page.dart` (Settings UI)

## 2. Dependencies
**Objective:** Ensure `pubspec.yaml` has all required packages for the new modules.
- **Action:** Verify/Add `shared_preferences`, `http`, `shizuku_api`.

## 3. Integration Steps
### A. Refactor/Fix Imports
- **Action:** Check files in `lib/autopilot/`. Ensure imports between them are correct relative to the `FlClash` project structure.
- **Example:** `import 'auto_pilot_service_configurable.dart';` might need to be absolute or relative depending on where they sit.

### B. Service Initialization
- **Objective:** Ensure `AutoPilotService` loads its config on app startup.
- **File:** `lib/main.dart` or `lib/setup.dart` (depending on FlClash architecture).
- **Action:** Call `await AutoPilotService().loadAndApplyConfig();` before `runApp`.

### C. UI Entry Point
- **Objective:** Make the Dashboard accessible.
- **Target File:** `lib/views/hysteria_settings.dart` (or the main ZIVPN/Hysteria menu).
- **Action:** Add a **ListTile** or **Button**:
  - **Title:** "Auto-Pilot Dashboard"
  - **Subtitle:** "Advanced Connection Recovery & Monitoring"
  - **OnTap:** Navigate to `AutoPilotDashboard()`.
  ```dart
  Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => const AutoPilotDashboard(),
  ));
  ```

## 4. Anti-Hallucination & Cleanup
1.  **Do NOT** rewrite the logic inside `lib/autopilot/*` unless necessary for fixing imports. Use them as the implementation source.
2.  **Conflict Resolution:** If you created a basic `lib/services/auto_pilot_service.dart` in a previous step, **DELETE IT**. The file `lib/autopilot/auto_pilot_service_configurable.dart` is the new authority.
3.  **Naming:** Ensure the class names in the reference files (`AutoPilotService`, `AutoPilotConfig`) do not conflict with existing FlClash classes.

## 5. Verification
- Run `flutter analyze lib/autopilot/` to ensure the copied files are valid in this project context.
