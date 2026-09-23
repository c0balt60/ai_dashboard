---
name: add-backend-operation
description: Add a new capability the app can ask the PC for (e.g. "restart agent", "list branches", "watch command output") end to end — AgentBackend contract, wire protocol, mock, PC server, HTTP client, providers, UI and tests. Use whenever a feature needs data or actions the backend doesn't expose yet.
---

# Add a backend operation

The UI only depends on `AgentBackend`. Three implementations must stay in step: `MockAgentBackend` (demo data), `LocalAgentBackend` (the PC server's real agents) and `HttpAgentBackend` (the app's client for the server). Every operation must be expressible as a JSON request or a WebSocket topic.

## Steps

1. **Contract** (`packages/agent_core/lib/src/backend/agent_backend.dart`):
   - One-shot actions return a `Future`.
   - Live data returns a `Stream` that emits a full snapshot straight away and again on every change, like the existing `watch*` methods.
   - A new data shape gets a model under `packages/agent_core/lib/src/models/` (immutable, handwritten `copyWith` when it gets updated, `fromJson`/`toJson` using the helpers in `json.dart`), exported from `models.dart`. Add it to the round trip in `packages/agent_core/test/json_test.dart`.
2. **Protocol** (`packages/agent_core/lib/src/protocol.dart`): add an `ApiPaths` entry for an action, or a `Topics` name plus a `watchTopicJson` case for a stream.
3. **Mock** (`packages/agent_core/lib/src/backend/mock_backend.dart`):
   - Mutate the in-memory maps and call `_notify()` once per logical change.
   - Use `_log(projectId, ...)` for project activity and `_addMessage(agentId, ...)` for chat or system events.
   - Simulate latency with `await Future<void>.delayed(latency)`. If the simulation should use the operation, extend `_tick()`, and keep behaviour deterministic when `simulate: false`.
   - For new data the UI should show, add realistic entries to `mock_seed.dart`.
4. **Server:**
   - Add the route in `server/lib/api.dart` (`_apiRouter`, using `action(...)`). Bad input should throw so it becomes a 400.
   - Implement it in `server/lib/local_backend.dart`. Anything that runs on the PC goes through `runShell` or a runner in `server/lib/runners/`, never string-built shell commands.
5. **Client:** implement it in `lib/data/backend/http_backend.dart` with `_request` (actions) or `_watch` (streams).
6. **Providers:** add a `StreamProvider`, or a derived `Provider`/`Provider.family`, in `lib/providers/backend_providers.dart`. Actions don't need providers: the UI calls `ref.read(backendProvider).method(...)`.
7. **UI:** call the operation from the relevant screen or sheet. Show progress while it runs, and a `SnackBar` or an inline result when it finishes. Remember it can now fail with a `BackendException`.
8. **Tests:** add a mock case to `packages/agent_core/test/mock_backend_test.dart`, a server case to `server/test/local_backend_test.dart` (fake runner) or `api_test.dart`, and extend `test/http_backend_test.dart` when the client needs more than a plain `_request`.
9. Run the `verify` skill. Commit contract and protocol, server, and app changes separately when they are sizeable.

## Rules
- Never put secrets (API keys, tokens) in code or seed data. The server token lives in the gitignored `server/config.json` or the `AI_DASHBOARD_TOKEN` environment variable; the app gets it from Settings.
- Changing the wire format incompatibly is a `major` version bump (see VERSIONING.md).
