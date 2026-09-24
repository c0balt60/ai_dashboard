# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Gemini CLI, Aider, …) working in this repo.

## What this project is

A **mobile-first Flutter app (Android is the primary target)** for monitoring and controlling AI coding agents that run on the owner's always-on main PC, which acts as the "server". The owner uses it while away from the computer to:

- prompt agents and chat with them
- run commands in project folders on the PC
- assign agents to a specific folder or task
- watch agent status, git branches, test results and task progress
- have several agents work on a project at the same time

**Current state:** every screen is built. The app shows either built-in demo data (`MockAgentBackend`) or the real PC through the **server in `server/`**, which drives the agent CLIs (`LocalAgentBackend`) and also serves the web build. Settings > Server switches between them. The phone reaches the PC over Tailscale (`tailscale serve` in front of the server, which listens on localhost only).

## Features and screens

| Screen | Route | Contents |
|---|---|---|
| Dashboard | `/dashboard` (tab) | PC connection and ping, stat tiles (active agents, running tasks, test pass rate, done in 24h), 7-day completion bars, active agents strip, recent projects, activity feed. A floating "Ask an agent" bar opens the chat of the most recently active agent (`defaultChatAgentProvider`) |
| Projects | `/projects` (tab) | All/Active filter; projects with running agents appear first |
| Project Dashboard | `/project/:id` (full screen) | Tabs: Overview (agents, branch, current task progress and steps), Tests (runs with failing tests), History (past tasks and activity log). A FAB opens "Run command" and an app-bar action opens "Assign agent" |
| Agents | `/agents` (tab) | Status filter chips and agent cards |
| Agent Screen (chat) | `/agent/:id` (full screen) | Centered agent title (tap to switch agent) with status pill, collapsible "Currently working on" banner, greeting with suggestion pills while empty, chat bubbles, typing indicator, quick-prompt chips, composer card (assign button, send); assign to folder/task, stop, clear |
| Tasks | `/tasks` (tab) | Two views picked by chips under the header. **Agent queue:** grouped as Active, Waiting, Backlog, Done (kanban columns on wide screens); cards read like "(Codex) Implement X · in project"; task details sheet. **My lists:** the user's own to-do lists (`TodoList`/`TodoItem`) with progress, timeline and overdue count. The FAB follows the view (New task / New list) |
| New Task | `/new-task?project=&title=&agent=` (full screen, all optional) | Assistant-style page: greeting, template chips and a suggest chip, and a composer card whose text becomes the task title, with project and agent dropdown buttons (`MenuAnchor`) inside it (no agent means backlog). Opened from the Tasks FAB, the dashboard "+" and a to-do's "send to agent", which prefills it |
| To-do list | `/list/:id` (full screen) | Open items soonest due first, collapsible Done. Items are tagged with projects and agents, have an optional start and due date, and can be handed off as a prefilled agent task. Rename, clear done, delete |
| Settings | `/settings` (tab) | Demo data / My PC switch, PC URL and access token, live connection status and test, simulation toggle (demo only), theme, notification toggles (not wired up yet). Everything is saved with shared_preferences |

**Agent status system:** `running`, `waiting`, `completed`, `failed` and `idle`. Every status, task-state, test, log, to-do due-date and PC-connection visual comes from `lib/widgets/status/status_visuals.dart`, so reuse `StatusDot`, `StatusBadge` and `AgentAvatar` instead of restyling them per screen.

## Architecture

```
packages/agent_core/        pure Dart, shared by app and server: models (with toJson/fromJson), the AgentBackend contract, MockAgentBackend + seed, protocol.dart (ApiPaths, Topics, WebSocket frames)
server/                     the PC server (shelf): bin/server.dart · lib/api.dart (REST + WebSocket + static web app) · local_backend.dart (real agents, state.json persistence) · runners/ (Claude Code, Codex, Gemini CLI, Aider) · process_utils.dart (runShell, git branch) · config.dart · tool/install_task.ps1 (autostart at log on)
lib/
  main.dart                 loads SharedPreferences, shows stray BackendExceptions as snackbars, ProviderScope(child: App())
  app/                      app.dart (MaterialApp.router) · app_version.dart (version shown in About) · router.dart (go_router + AppRoutes) · shell_scaffold.dart (bottom NavigationBar, side rail from 840dp) · theme.dart (M3 light/dark + StatusColors and AppSurfaces ThemeExtensions)
  data/models/models.dart   re-exports package:agent_core/models.dart
  data/backend/             http_backend.dart (HttpAgentBackend, ConnectionStatus, BackendException) · socket_connect*.dart (WebSocket with native pings)
  providers/                backend_providers.dart (streams + derived views) · settings_provider.dart
  widgets/                  shared cards (AgentCard, TaskCard, ProjectCard), common.dart (SectionHeader, EmptyState, AsyncValueView, StatTile, InfoChip)
                            page.dart (AppPage, PageHeader, HeaderAction, ThemeToggleButton) · layout.dart (Breakpoints, AppBackdrop, ContentWidth, ResponsiveGrid) · prompt_bar.dart (AiOrb, PromptBarFrame, PromptGreeting, SuggestionPill, submitOnEnter) · glow.dart (FloatingGlow, BottomHaze)
  widgets/status/           status system (see above)
  widgets/sheets/           app_sheet (showAppSheet, SheetHeader) · assign_agent, run_command, todo_list, todo_item bottom sheets
  features/<area>/          one folder per screen area
  utils/time_format.dart    timeAgo, formatDuration, clockTime
tool/bump_version.dart      bumps pubspec.yaml and lib/app/app_version.dart together
```

### Data flow
- The UI never touches a backend class directly.
  - It watches providers in `backend_providers.dart` (`agentsProvider`, `projectsProvider`, `tasksProvider`, `messagesProvider(id)`, plus derived ones like `agentProvider(id)`, `tasksByStateProvider` and `dashboardStatsProvider`).
  - It triggers actions with `ref.read(backendProvider).someAction(...)`.
- **`AgentBackend`** (`packages/agent_core/lib/src/backend/agent_backend.dart`) is the only contract with the PC. Each `watch*` stream emits a full snapshot straight away and again on every change.
- **`backendProvider`** builds a `MockAgentBackend` or an `HttpAgentBackend` from the settings (mode, URL, token); changing them swaps the backend. `connectionStatusProvider` exposes the live link (null in demo mode).
- **`MockAgentBackend`** keeps state in memory. A `Timer.periodic` tick (every 3s) moves tasks forward, completes or fails them, promotes waiting tasks and adds test runs. Prompts get canned replies after `latency`. `simulate: false, latency: Duration.zero` makes it deterministic for tests.
- **Wire protocol** (`protocol.dart`): actions are JSON requests under `/api` with `Authorization: Bearer <token>`; streams are topics on one WebSocket at `/api/ws` (token in the `token` query parameter), answered with full snapshots. `HttpAgentBackend` reconnects with backoff and re-subscribes.
- **`LocalAgentBackend`** (server): agents and projects come from `server/config.json`. One turn per agent at a time, each a CLI process in the agent's folder with the prompt on stdin; the CLI session id is kept so the next turn resumes the conversation. Tasks queued for an agent start when it is free, and a finished task runs the project's `testCommand`. `runCommand` goes through PowerShell `-EncodedCommand` on Windows. State persists to `state.json` in the data dir.

### Navigation
- The five tabs sit in a `StatefulShellRoute.indexedStack`, so each tab keeps its own back stack.
- Project and agent detail routes are top-level routes on the root navigator, so they cover the nav bar.
- Use `context.push(AppRoutes.project(id))` or `AppRoutes.agent(id)` for detail screens, and `context.go(AppRoutes.tasks)` etc. to switch tabs.

## Tech stack and API notes

- Flutter 3.47 / Dart 3.13. Switch expressions, records, patterns and dot-shorthands are all fine.
- **flutter_riverpod 3.x:**
  - `StateProvider` is legacy, so don't use it. Use a `Notifier`, or keep local UI state in `State`.
  - Family arguments go through the constructor.
  - `AsyncValue.value` is nullable.
  - No code generation, no freezed and no build_runner.
- **go_router 18.**
- Keep dependencies minimal. Add a package only when it clearly pays for itself.
- When unsure of an API, read the source in `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\` or `C:\Users\elmtc\flutter\packages\flutter\lib` instead of guessing, and avoid deprecated APIs.

## UI rules (mobile first, web friendly)

- Tab screens are built with `AppPage` (large title header, round `HeaderAction`s, theme toggle, centering gutter, pull-to-refresh). Don't give them their own Scaffold/AppBar or background; the shell paints `AppBackdrop`.
- Detail screens use `AppBackdrop(child: Scaffold(backgroundColor: Colors.transparent, ...))`.
- Cards are borderless on the backdrop (radius 24, `AppSurfaces.card`). Pastel tiles use `AppSurfaces.tint(accent, brightness)`.
- Anything floating over content (prompt bars, FABs) gets `FloatingGlow` rather than a Material elevation shadow. `AppPage` does this for its FAB and `bottomBar`, and adds a `BottomHaze` behind them.
- From 840dp the shell shows a side rail and content centers at max 1100dp. Card lists go in `ResponsiveGrid`. Keep scroll views full width and center with padding, so the mouse wheel works anywhere. Never wrap a `LayoutBuilder` in `IntrinsicHeight`.
- Single-column layouts, 16px side padding, touch targets of at least 48dp, and `SafeArea` everywhere.
- Actions open modal bottom sheets. Open them with `showAppSheet` and start them with a `SheetHeader`: phones get a drag handle, desktop windows (`Breakpoints.isDesktop`) get a close button instead. Sheets add bottom padding from `MediaQuery.viewInsets` so the keyboard never covers inputs.
- Primary actions go in FABs, filters in horizontally scrolling chips, and refreshes use pull-to-refresh.
- Colors come from the theme `ColorScheme` or `StatusColors.of(context)`. Never hardcode colors, except in the monospace terminal output box.
- Text in a `Row` must be able to shrink: use `Expanded`/`Flexible` with `TextOverflow.ellipsis`. The smoke test runs at 360dp wide and fails on overflows.
- Always dispose controllers (`TextEditingController`, `AnimationController`).

## Code conventions (owner preferences)

- **Comments:** only file- and class-level doc comments, plus comments on genuinely tricky logic. No section-divider comments and no per-field or obvious comments.
- **Commits:** split work into several logical commits (dependencies, then data layer, then shared widgets, then each feature, then tests). Never dump everything into one commit, and don't commit straight to `main`; use a feature branch.
- **Versioning:** every change set bumps the version, which shows in Settings > About. Pick `major`, `minor`, `patch` or `build` as described in `VERSIONING.md`, run `tool/bump_version.dart`, and commit the bump on its own as the last commit (`Bump version to X.Y.Z`). Never edit the version by hand.
- **Releases:** when a new `major.minor.patch` reaches `main`, `.github/workflows/android-release.yml` tests the app, builds signed APKs and publishes them as the GitHub release `vX.Y.Z`, which the phone updates from. `build` bumps don't create a release.
- Match the surrounding code style. Run `dart format` before committing.
- **Secrets:** never commit API keys or tokens. The server token lives in the gitignored `server/config.json` (or `AI_DASHBOARD_TOKEN`); the app stores it from Settings. The Android keystore and `android/key.properties` are gitignored too.

## Commands

Flutter is **not on PATH** on the owner's machine, so use full paths:

```powershell
C:\Users\elmtc\flutter\bin\cache\dart-sdk\bin\dart.exe format lib test
C:\Users\elmtc\flutter\bin\flutter.bat analyze          # must report "No issues found!"
C:\Users\elmtc\flutter\bin\flutter.bat test
C:\Users\elmtc\flutter\bin\cache\dart-sdk\bin\dart.exe tool/bump_version.dart patch   # or major | minor | build, see VERSIONING.md
C:\Users\elmtc\flutter\bin\flutter.bat run -d edge      # web testing (Chrome isn't installed; Edge is)
C:\Users\elmtc\flutter\bin\flutter.bat run -d web-server --web-hostname 0.0.0.0 --web-port 8080   # open from a phone on the LAN
C:\Users\elmtc\flutter\bin\flutter.bat build web --release   # the server serves build/web

# From server/ (needs config.json, see config.example.json):
C:\Users\elmtc\flutter\bin\cache\dart-sdk\bin\dart.exe run bin/server.dart --simulate   # mock agents
C:\Users\elmtc\flutter\bin\cache\dart-sdk\bin\dart.exe run bin/server.dart              # real agents
C:\Users\elmtc\flutter\bin\cache\dart-sdk\bin\dart.exe test
```

Only build an APK when asked: `flutter.bat build apk --release --split-per-abi` (signed when `android/key.properties` exists).

## Testing

- `test/widget_test.dart` is the smoke test. It overrides `backendProvider` with `MockAgentBackend(simulate: false, latency: Duration.zero)`, visits every tab and pushes the agent-chat and project routes, once on a phone view (1080×2340 at 3x) and once on a desktop view (1440×900 at 1x, via the side rail). It also checks the header theme toggle.
- `test/http_backend_test.dart` runs `HttpAgentBackend` against the real server handler in-process (streams, actions, wrong token, reconnect). `test/settings_test.dart` checks settings persistence.
- `packages/agent_core/test/` covers the mock and the JSON/protocol round trips. `server/test/` covers the API, the runners (fixtures plus a fake CLI) and `LocalAgentBackend` (with a fake runner).
- `test/version_test.dart` checks that `lib/app/app_version.dart` matches the `pubspec.yaml` version.
- Status dots animate forever, so **never use `pumpAndSettle`**. Use `pump(const Duration(...))` instead.
- Keep the suite small and meaningful, and run it once per change rather than repeatedly.

## Known gaps / next steps

- Only the Claude Code runner follows a checked output format. The Codex, Gemini CLI and Aider runners follow their documented flags and should be verified against the installed versions.
- Most screens fire backend actions without catching errors. `main.dart` shows failed requests as a snackbar, but sheets don't reset their busy state on failure.
- The notification toggles are UI only; push notifications don't exist yet.
- Web uses path URLs. The server falls back to `index.html`, but any other static host would need the same rewrite.
