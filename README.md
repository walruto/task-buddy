# Task Buddy

Task Buddy is a macOS 14+ desktop companion for Apple Reminders, Apple Calendar, recent Apple Mail Inbox messages, and optional phone task sync through Supabase. It uses the supplied beanie character in a draggable floating panel and schedules quiet local reminders. There is no Google Cloud project, Google OAuth client, or analytics.

Buddy Tasks use Supabase when phone sync is connected and otherwise fall back to Apple Reminders. Existing Google Tasks are not imported, synchronized, or displayed.

## Phone task sync

The `supabase/` directory contains the `buddy_tasks` migration with per-user Row Level Security. The dependency-free phone interface lives in `mobile/` and is bundled into the small Android WebView app in `android/`.

1. Copy `Sources/TaskBuddyApp/Resources/SupabaseConfig.example.json` to `SupabaseConfig.json` and fill in the project URL and publishable key.
2. Copy `mobile/config.example.js` to `mobile/config.js` with the same public values.
3. Apply the migration with `npx supabase db push --remote`.
4. Build the installable APK with `./scripts/package-android.sh`. The result is `dist/TaskBuddy-Android.apk`.
5. Install the APK on Android, create an account, confirm its email if prompted, and use the same email and password in the Mac app's **Phone sync — Supabase** card.

While both apps are connected, Supabase Realtime refreshes task additions and completions immediately. Tasks can have a date, deadline time, and category. Android schedules one native notification at the selected local deadline time after the phone has synced it; undated tasks do not schedule alerts.

## Lock In Focus Lab

Every phone/web task includes a **Focus** action. It opens Task Buddy's on-device Focus Lab with 25, 45, and 60-minute blocks, Screen Work and Paper Homework modes, three sensitivity levels, calibration, pause/resume, and session statistics. Completed and manually ended sessions save aggregate timing, focus percentage inputs, longest streak, and alert count to the per-user `focus_sessions` table.

The camera preview and face landmarks are processed inside the browser with the pinned `@mediapipe/tasks-vision@1.1.1` Face Landmarker. Frames, landmarks, calibration samples, and the live timeline are never sent to Supabase, recorded, or permanently stored. The first focus session needs internet access to download the pinned MediaPipe runtime and model. Camera access requires HTTPS, localhost, or the Android app's secure local asset origin.

Attention detection is an estimate based on face presence, head direction, coarse gaze, eye openness, and tab visibility. It does not perform identity or emotion recognition and is not a medical or accessibility diagnostic.

Only the publishable key belongs in either client. Never put a Supabase secret/service-role key in the app. Users sign in through Supabase Auth, and Row Level Security limits every task row to its owner.

The personal APK uses Android's debug signature and is distributed outside Google Play. Android will therefore ask the user to approve installation from the browser or file manager used to open it.

## Requirements

- macOS 14 or newer
- Xcode 15.3 or newer with the Swift 5.10 toolchain
- ImageMagick only when regenerating sprites or the app icon (`brew install imagemagick`)

## Local setup

1. Launch Task Buddy and allow access to Reminders and Calendar. Either permission can be skipped and enabled later in the Buddy Control Center.
2. Add Gmail or another account to Apple Mail.
3. Click **Connect Apple Mail** in Task Buddy and allow the macOS Automation permission.

## Run and test

```sh
swift run TaskBuddy
swift test
```

Running through SwiftPM is convenient for development but cannot fully exercise launch-at-login. For the intended app behavior, build the app bundle:

```sh
./scripts/package-app.sh
ditto "dist/Task Buddy.app" "/Applications/Task Buddy.app"
open "/Applications/Task Buddy.app"
```

Move the packaged app into `/Applications` before enabling launch at login. The script creates an ad-hoc signed personal build; public distribution would require a Developer ID signature and notarization.

The installed app can be launched from Applications, Launchpad, Spotlight, or a Finder alias. Its monochrome Buddy-face menu-bar icon provides **Open Buddy**, **Buddy Control Center**, **Sync Now**, and **Quit Task Buddy** without reopening a terminal.

## Character assets

Runtime frames live in `Sources/TaskBuddyApp/Resources/Character/` and must be transparent 256×256 PNGs with a common baseline:

```text
idle-1.png       idle-2.png
wave-1.png       wave-2.png
thinking-1.png   thinking-2.png
alert-1.png      alert-2.png
error-1.png      error-2.png
happy-1.png      happy-2.png
```

The current files were extracted directly from the supplied character sheets. Replace them with the original transparent exports using the same filenames for cleaner edges. To rebuild the fallback set, run `./scripts/prepare-character-assets.sh`.

## Privacy and behavior

- Task Buddy uses the accounts already configured in Apple Mail and stores no mail password.
- Cached reminder, event, and email metadata stays in `~/Library/Application Support/TaskBuddy`.
- Task Buddy polls every 15 minutes and after launch, wake, network recovery, or manual refresh.
- The newest 20 Apple Mail Inbox messages appear as locally dismissible, display-only items. Mail is not modified and message bodies are not read.
- All available Reminders lists and Calendar calendars are shown. Calendar accounts already added to macOS work through EventKit.
- **Buddy Tasks** in the Control Center provides a lightweight task list: add a title, category, and optional due date and time, then complete it from the dashboard or reminder bubble. Tasks sync through Supabase when connected and otherwise use Apple Reminders.
- Google Tasks is intentionally not connected. Supporting it would require Google OAuth or a Google-hosted bridge such as Apps Script.
- The buddy floats above normal and fullscreen app windows on every desktop until Task Buddy is explicitly quit.
- Open **Buddy Control Center** from the Dock or the pet’s right-click menu. Closing the Control Center does not close the buddy.
- Use the **Buddy size** slider to resize it from 50% to 200%; drag the buddy itself to reposition it.
