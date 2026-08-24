# Aegis Remote Mobile

Pure React Native CLI client (no Expo) for the existing Phase 11 Remote Gateway. It only sends natural-language commands and approval decisions; AegisDesktop remains the execution authority.

## Requirements

- Node >= 20
- JDK 17 for Android builds (e.g. `/Library/Java/JavaVirtualMachines/microsoft-17.jdk`, or any JDK 17 install) — set `JAVA_HOME` before running Gradle
- Xcode + CocoaPods for iOS builds
- Android SDK at `$ANDROID_HOME` (write `android/local.properties` locally; it is gitignored)

## Development

```sh
npm install
npm run typecheck
npm run lint
npm test
npm start          # Metro
npm run android     # or: npx react-native run-android
npm run ios         # or: npx react-native run-ios
```

Android release build:

```sh
cd android
JAVA_HOME=/Library/Java/JavaVirtualMachines/microsoft-17.jdk/Contents/Home ./gradlew assembleRelease
```

The app registers through `/v1/devices/register`, stores the issued device credential in iOS Keychain / Android Keystore-backed secure storage via `react-native-keychain`, and never stores the master remote token.

## Private HTTP limitation

The current Gateway uses a numeric Tailscale HTTP URL. Native transport configuration therefore permits cleartext requests (Android via `res/xml/network_security_config.xml`, iOS via `NSAllowsLocalNetworking`), while the API client rejects cleartext hosts outside loopback, RFC1918, and Tailscale CGNAT (`100.64.0.0/10`). Move to Tailscale HTTPS/MagicDNS to restore transport encryption and allow tighter native domain declarations.

No microphone permission is requested; voice remains disabled.
