# HabitLoop

HabitLoop is a Flutter habit tracker for Android and iOS. It supports recurring and one-time tasks, local reminders, a progress calendar, searchable task icons, and daily quotes with an offline fallback. Firebase Authentication and Cloud Firestore keep accounts, tasks, and progress in sync.

## Run locally

Install Flutter and set up a phone or simulator. Android builds use SDK Platform 37. For iOS development, use macOS and Xcode. Run `flutter doctor` to check your toolchain.

1. Create or select a Firebase project you control. Enable Email/Password authentication and create a Cloud Firestore database. Register the Android and iOS apps with the package and bundle ID `com.habitloop.habitloop`.
2. From the repository root, configure the app using the Firebase CLI and FlutterFire CLI.

   ```bash
   firebase login
   dart pub global activate flutterfire_cli
   flutterfire configure --project=YOUR_FIREBASE_PROJECT_ID --platforms=android,ios
   flutter pub get
   ```

3. Provision a regular test account. The app turns a username into `USERNAME@habitloop.example` for Firebase sign-in. Create that Auth account and add its profile in Firestore at `users/{uid}` with `username`, `displayName`, `role: user`, and `disabled: false`.
4. Review the included Firestore rules and indexes before deploying them to your development project. Then run the app.

   ```bash
   firebase deploy --config firebase.rules.json --only firestore:rules,firestore:indexes --project YOUR_FIREBASE_PROJECT_ID
   flutter devices
   flutter run -d DEVICE_ID
   ```

The Firebase options, native Firebase configuration, signing keys, and build outputs are generated locally and ignored by Git. The admin web portal is maintained separately.

## Tests and Android APK

```bash
flutter test
flutter build apk --debug
```

The test APK is written to `build/app/outputs/flutter-apk/app-debug.apk`. For store distribution, configure release signing separately.
