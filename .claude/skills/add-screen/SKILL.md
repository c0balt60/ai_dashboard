---
name: add-screen
description: Add a new screen to the app — either a bottom-nav tab or a full-screen detail route — wired into go_router, AppRoutes and the smoke test. Use when the user asks for a new page/screen/tab.
---

# Add a screen

Read `lib/app/router.dart` and `lib/app/shell_scaffold.dart` first.

## 1. Decide the kind of screen
- **Tab:** a top-level area that appears in the bottom nav. There are 5 tabs today and Material recommends at most 5. Before adding a sixth, ask the user whether an existing tab should link to the new screen instead.
- **Detail route:** a screen for a single entity, or a focused task such as a chat. It sits at the top level on the root navigator and covers the nav bar.

## 2. Create the screen
- Put it at `lib/features/<area>/<name>_screen.dart`, as a `ConsumerWidget` or `ConsumerStatefulWidget`.
- A detail screen takes its id through the constructor (`required String fooId`).
- Read data through providers in `lib/providers/backend_providers.dart`. If you need a new derived view, add a provider there rather than filtering inside `build`.
- Use the shared widgets: `SectionHeader`, `EmptyState`, `AsyncValueView`, `StatTile`, `InfoChip`, the cards, and the status widgets.
- Handle an unknown id with an `EmptyState`, and show a loading state while the streams haven't emitted yet.
- Follow the UI rules in AGENTS.md: mobile first, `SafeArea`, flexible text in rows, bottom sheets for actions.

## 3. Wire up routing
- Add a path constant or builder to `AppRoutes`:
  - a tab: `static const foo = '/foo';`
  - a detail route: `static String foo(String id) => '/foo/$id';`
- For a tab, add a `_tab(...)` branch in `routerProvider` and a `NavigationDestination` in `ShellScaffold._destinations`, in the same order.
- For a detail route, add a top-level `GoRoute(path: '/foo/:id', ...)` next to the existing `/project/:id` and `/agent/:id`.
- Navigate with `context.push(AppRoutes.foo(id))` for details or `context.go(AppRoutes.foo)` for tabs.

## 4. Extend the smoke test
In `test/widget_test.dart`:
- for a tab, add the nav label and screen type to the `tabs` map
- for a detail route, add a `router.push(...)` step followed by `expect(find.byType(FooScreen), findsOneWidget)`

## 5. Verify and commit
Run the `verify` skill, then commit the screen as its own commit, for example "Add foo screen".
