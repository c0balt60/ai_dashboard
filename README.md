# AI Dashboard

A mobile-first Flutter app for monitoring and controlling AI coding agents (Claude Code, Codex, Gemini CLI, Aider) that run on your PC. The PC runs a small Dart server that drives the agent CLIs. The app connects to it, or runs on built-in demo data.

```
packages/agent_core/   shared models, backend contract and mock (pure Dart)
server/                the PC server
lib/                   the Flutter app
```

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) 3.47 (includes Dart 3.13)
- The agent CLIs you want to use, installed and logged in on the PC (for example `claude`)
- [Tailscale](https://tailscale.com/) on the PC and the phone, to reach the server from outside your network
- For Android builds: the Android SDK and a JDK

If Flutter isn't on your `PATH`, use full paths such as `C:\Users\<you>\flutter\bin\flutter.bat` and `C:\Users\<you>\flutter\bin\cache\dart-sdk\bin\dart.exe` in the commands below.

Fetch dependencies once:

```powershell
flutter pub get
cd server; dart pub get
```

## Run the app

The app starts on demo data, so you can try it without the server.

```powershell
flutter run -d edge                    # in a browser (or -d chrome)
flutter run -d <device-id>             # on a connected Android phone (see: flutter devices)
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080   # open from a phone on the same LAN
```

To use your PC instead of demo data, open **Settings > Server**, choose **My PC**, and enter the server URL and access token.

## Run the PC server

1. Copy `server/config.example.json` to `server/config.json` (git ignores it) and fill it in:
   - `token`: a long random string; the app sends it with every request
   - `projects`: the folders agents work in, each with an optional `testCommand`
   - `agents`: one entry per agent, with its `type` (`claudeCode`, `codex`, `geminiCli`, `aider`) and any `extraArgs` for the CLI
2. Start it from `server/`:

   ```powershell
   dart run bin/server.dart --simulate   # mock agents, no CLIs needed
   dart run bin/server.dart              # real agents
   ```

   Options: `--config <file>` (default `config.json`), `--log <file>`.

The server listens on `127.0.0.1:8787` and also serves the web build from `build/web` (see [Build](#build)). Its state is stored in `%APPDATA%\ai_dashboard`.

### Reach it from your phone

The server only listens on localhost, so put Tailscale in front of it:

```powershell
tailscale serve --bg 8787
```

Then use the `https://<pc-name>.<tailnet>.ts.net` address as the server URL in the app.

### Start it automatically at log on (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File server/tool/install_task.ps1
```

This compiles the server to `server/ai_dashboard_server.exe` and registers a Task Scheduler task that runs it at log on, logging to `server/server.log`. Run it again after pulling changes to rebuild and restart. Remove it with `Unregister-ScheduledTask -TaskName AiDashboardServer`.

## Build

```powershell
flutter build web --release                    # output in build/web, served by the PC server
flutter build apk --release --split-per-abi    # Android APKs in build/app/outputs/flutter-apk
```

Release APKs are signed when `android/key.properties` exists; copy `android/key.properties.example` and follow the steps in it. Without it, the build uses the debug key.

Push notifications need `android/app/google-services.json` from Firebase and a service-account key set as `firebaseServiceAccount` in `server/config.json`. Without them the app builds and runs normally, just without push.

## Test

```powershell
dart format lib test packages server
flutter analyze
flutter test
cd packages/agent_core; dart test
cd server; dart test
```

## Releases and versioning

Every change bumps the version with `dart tool/bump_version.dart <major|minor|patch|build>`; see [VERSIONING.md](VERSIONING.md). When a new `major.minor.patch` version reaches `main`, GitHub Actions builds signed APKs and publishes them as release `vX.Y.Z`, which the app can update from.
