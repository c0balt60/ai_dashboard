# Versioning

Every change to the project changes the version. The version is shown in **Settings > About** as `Version 1.4.2 (build 37)`, so you can always tell which build is running on the phone.

## Format

```
version: MAJOR.MINOR.PATCH+BUILD      (pubspec.yaml)
```

- `MAJOR.MINOR.PATCH` follows [Semantic Versioning](https://semver.org). Android shows it as `versionName`.
- `BUILD` is a counter that goes up by one on **every** bump and never resets. Android uses it as `versionCode`, which must always increase for an update to install over the old APK.

## Where the version lives

| File | Role |
|---|---|
| `pubspec.yaml` (`version:`) | Source of truth. Flutter reads it for the Android, iOS, web and desktop builds. |
| `lib/app/app_version.dart` | The same value as Dart constants (`appVersion`, `appBuildNumber`), shown in Settings > About. |
| `tool/bump_version.dart` | Updates both files at once. |
| `test/version_test.dart` | Fails if the two files disagree. |

Never edit the version by hand. Use the script:

```powershell
C:\Users\elmtc\flutter\bin\cache\dart-sdk\bin\dart.exe tool/bump_version.dart patch   # or major | minor | build
```

## Which part to bump

Pick the **highest** row that applies to the change set.

| Bump | When | Examples |
|---|---|---|
| `major` | A change that breaks compatibility with the PC server or with saved data, or removes something users rely on. | Incompatible change to the `AgentBackend` contract or its wire format; persisted settings that old builds can't read; removing a screen or tab. |
| `minor` | A new user-visible feature. | New screen, tab, sheet or backend operation; new setting; a new view or filter on an existing screen. |
| `patch` | A fix or change to existing behaviour that adds no feature. | Bug and overflow fixes; restyling or layout tweaks; copy changes; mock backend behaviour; dependency updates; performance work. |
| `build` | A change that doesn't affect the app at all. | Docs, tests, lint config, agent skills and instructions, repo tooling. |

`major`, `minor` and `patch` reset the parts to their right (`1.4.2` → `1.5.0`) and also add one to `BUILD`. `build` only adds one to `BUILD`.

## When to bump

- Bump **once per change set**, meaning one feature, fix or request, not once per commit. A feature split into several commits gets one bump.
- Make the bump the last commit of the change set, on its own: `Bump version to 1.5.0`. It contains only `pubspec.yaml` and `lib/app/app_version.dart`.
- If a change set holds several kinds of change, the highest one wins: a new feature plus a bug fix is a `minor`.
- Run the tests after bumping. `test/version_test.dart` catches a hand-edited or half-applied version.

## Before 1.0 of the real backend

The app still runs on the in-app mock backend. Until the real PC server exists, `AgentBackend` changes only need a `major` bump when they would break a server that is actually deployed; otherwise treat them as `minor`.
