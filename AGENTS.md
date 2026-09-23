# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Gemini CLI, Aider, …) working in this repo.

## What this project is

A **mobile-first Flutter app (Android is the primary target)** for monitoring and controlling AI coding agents that run on the owner's always-on main PC, which acts as the "server". The owner uses it while away from the computer to:

- prompt agents and chat with them
- run commands in project folders on the PC
- assign agents to a specific folder or task
- watch agent status, git branches, test results and task progress
- have several agents work on a project at the same time

**Current state:** every screen is built, and the data comes from an **in-app mock backend** (`MockAgentBackend`). There is no real PC server yet.

## Features and screens

| Screen | Route | Contents |
|---|---|---|
| Dashboard | `/dashboard` (tab) | PC connection and ping, stat tiles (active agents, running tasks, test pass rate, done in 24h), 7-day completion bars, active agents strip, recent projects, activity feed |
| Projects | `/projects` (tab) | All/Active filter; projects with running agents appear first |
| Project Dashboard | `/project/:id` (full screen) | Tabs: Overview (agents, branch, current task progress and steps), Tests (runs with failing tests), History (past tasks and activity log). A FAB opens "Run command" and an app-bar action opens "Assign agent" |
| Agents | `/agents` (tab) | Status filter chips and agent cards |
| Agent Screen (chat) | `/agent/:id` (full screen) | "Currently working on" banner, chat bubbles, typing indicator, quick prompts, composer; assign to folder/task, stop, clear |
| Tasks | `/tasks` (tab) | Queue grouped as Active, Waiting, Backlog, Done. Cards read like "(Codex) Implement X · in project". New-task sheet and details sheet |
| Settings | `/settings` (tab) | PC URL and connection test, simulation toggle, theme, notification toggles (not wired up yet) |

**Agent status system:** `running`, `waiting`, `completed`, `failed` and `idle`. Every status, task-state, test and log visual comes from `lib/widgets/status/status_visuals.dart`, so reuse `StatusDot`, `StatusBadge` and `AgentAvatar` instead of restyling them per screen.

## Architecture

```
lib/
  main.dart                 ProviderScope(child: App())
  app/                      app.dart (MaterialApp.router) · router.dart (go_router + AppRoutes) · shell_scaffold.dart (bottom NavigationBar) · theme.dart (M3 light/dark + StatusColors ThemeExtension)
  data/models/              immutable models with handwritten copyWith; models.dart re-exports them all
  data/backend/             agent_backend.dart (abstract contract) · mock_backend.dart · mock_seed.dart
  providers/                backend_providers.dart (streams + derived views) · settings_provider.dart
  widgets/                  shared cards (AgentCard, TaskCard, ProjectCard), common.dart (SectionHeader, EmptyState, AsyncValueView, StatTile, InfoChip)
  widgets/status/           status system (see above)
  widgets/sheets/           assign_agent, new_task, run_command bottom sheets
  features/<area>/          one folder per screen area
  utils/time_format.dart    timeAgo, formatDuration, clockTime
```

### Data flow
- The UI never touches a backend class directly.
  - It watches providers in `backend_providers.dart` (`agentsProvider`, `projectsProvider`, `tasksProvider`, `messagesProvider(id)`, plus derived ones like `agentProvider(id)`, `tasksByStateProvider` and `dashboardStatsProvider`).
  - It triggers actions with `ref.read(backendProvider).someAction(...)`.
- **`AgentBackend`** (`lib/data/backend/agent_backend.dart`) is the only contract with the PC. Each `watch*` stream emits a full snapshot straight away and again on every change.
- **`MockAgentBackend`** keeps state in memory. A `Timer.periodic` tick (every 3s) moves tasks forward, completes or fails them, promotes waiting tasks and adds test runs. Prompts get canned replies after `latency`. `simulate: false, latency: Duration.zero` makes it deterministic for tests.
- **Future real backend:** add an `HttpAgentBackend implements AgentBackend` (REST plus WebSocket to a small server on the PC that wraps the agent CLIs), then swap it in `backendProvider`. No UI changes should be needed.

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

## UI rules (mobile first)

- Single-column layouts, 16px side padding, touch targets of at least 48dp, and `SafeArea` everywhere.
- Actions open modal bottom sheets. Sheets that can open from a tab use `useRootNavigator: true` and `isScrollControlled`, and add bottom padding from `MediaQuery.viewInsets` so the keyboard never covers inputs.
- Primary actions go in FABs, filters in horizontally scrolling chips, and refreshes use pull-to-refresh.
- Colors come from the theme `ColorScheme` or `StatusColors.of(context)`. Never hardcode colors, except in the monospace terminal output box.
- Text in a `Row` must be able to shrink: use `Expanded`/`Flexible` with `TextOverflow.ellipsis`. The smoke test runs at 360dp wide and fails on overflows.
- Always dispose controllers (`TextEditingController`, `AnimationController`).

## Code conventions (owner preferences)

- **Comments:** only file- and class-level doc comments, plus comments on genuinely tricky logic. No section-divider comments and no per-field or obvious comments.
- **Commits:** split work into several logical commits (dependencies, then data layer, then shared widgets, then each feature, then tests). Never dump everything into one commit, and don't commit straight to `main`; use a feature branch.
- Match the surrounding code style. Run `dart format` before committing.
- **Secrets:** never commit API keys or tokens. When a real backend arrives, keep secrets in a gitignored `.env` file, `--dart-define`, or platform secure storage.

## Commands

Flutter is **not on PATH** on the owner's machine, so use full paths:

```powershell
C:\Users\elmtc\flutter\bin\cache\dart-sdk\bin\dart.exe format lib test
C:\Users\elmtc\flutter\bin\flutter.bat analyze          # must report "No issues found!"
C:\Users\elmtc\flutter\bin\flutter.bat test
C:\Users\elmtc\flutter\bin\flutter.bat run -d edge      # web testing (Chrome isn't installed; Edge is)
C:\Users\elmtc\flutter\bin\flutter.bat run -d web-server --web-hostname 0.0.0.0 --web-port 8080   # open from a phone on the LAN
```

## Testing

- `test/widget_test.dart` is the smoke test. It sets a phone-sized view (1080×2340 at 3x), overrides `backendProvider` with `MockAgentBackend(simulate: false, latency: Duration.zero)`, visits every tab, and pushes the agent-chat and project routes.
- `test/mock_backend_test.dart` holds unit tests for mock behaviour.
- Status dots animate forever, so **never use `pumpAndSettle`**. Use `pump(const Duration(...))` instead.
- Keep the suite small and meaningful, and run it once per change rather than repeatedly.

## Known gaps / next steps

- There is no real PC backend or server yet, and no authentication.
- Settings are in memory only and not persisted.
- The notification toggles are UI only; push notifications don't exist yet.
- The layout doesn't adapt to tablet or desktop widths (by design, since the app is mobile first).
