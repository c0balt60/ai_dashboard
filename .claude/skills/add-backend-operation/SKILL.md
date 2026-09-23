---
name: add-backend-operation
description: Add a new capability the app can ask the PC for (e.g. "restart agent", "list branches", "watch command output") end to end — AgentBackend contract, MockAgentBackend behaviour, providers, UI and a test. Use whenever a feature needs data or actions the backend doesn't expose yet.
---

# Add a backend operation

The UI must only depend on `AgentBackend`, so a future real backend (`HttpAgentBackend`) can replace the mock with no UI changes. Keep every operation expressible as a REST call or a WebSocket stream.

## Steps

1. **Contract:** add the method to `lib/data/backend/agent_backend.dart`.
   - One-shot actions return a `Future`.
   - Live data returns a `Stream` that emits a full snapshot straight away and again on every change, like the existing `watch*` methods.
   - If a new data shape is needed, add a model under `lib/data/models/` (immutable, with a handwritten `copyWith` when it gets updated) and export it from `models.dart`.
2. **Mock:** implement it in `lib/data/backend/mock_backend.dart`.
   - Mutate the in-memory maps and call `_notify()` once per logical change.
   - Use `_log(projectId, ...)` for project activity and `_addMessage(agentId, ...)` for chat or system events.
   - Simulate latency with `await Future<void>.delayed(latency)`.
   - If the simulation should use the operation, extend `_tick()`. Keep the behaviour deterministic when `simulate: false`.
   - For new data the UI should show, add realistic entries to `mock_seed.dart`.
3. **Providers:**
   - Add a `StreamProvider` for new streams, or a derived `Provider`/`Provider.family` in `lib/providers/backend_providers.dart` for UI-ready views.
   - Actions don't need providers: the UI calls `ref.read(backendProvider).method(...)`.
4. **UI:** call the operation from the relevant screen or sheet. Show progress while it runs, and a `SnackBar` or an inline result when it finishes.
5. **Test:** add a focused case to `test/mock_backend_test.dart` using `MockAgentBackend(simulate: false, latency: Duration.zero)` and `addTearDown(backend.dispose)`.
6. Run the `verify` skill. Commit the contract, mock and provider changes separately from the UI change when both are sizeable.

## Rules
- Never put secrets (API keys, tokens) in code or seed data. Real credentials belong in a gitignored `.env` file, `--dart-define`, or secure storage.
- Keep the mock in-app. Only build a separate server if the user explicitly asks for one.
