---
name: verify
description: Format, analyze and test this Flutter project using the full SDK paths (Flutter is not on PATH). Use after code changes and before committing.
---

# Verify

Run the steps below from the project root. Stop at the first step that fails, fix the problem, and re-run only that step.

1. Format:
   `C:\Users\elmtc\flutter\bin\cache\dart-sdk\bin\dart.exe format lib test packages server`
2. Analyze. It must print `No issues found!` (this also covers `packages/` and `server/`):
   `C:\Users\elmtc\flutter\bin\flutter.bat analyze`
3. Test the app:
   `C:\Users\elmtc\flutter\bin\flutter.bat test`
4. Only if `packages/agent_core` or `server` changed, test them too, from their folders:
   `C:\Users\elmtc\flutter\bin\cache\dart-sdk\bin\dart.exe test`

## Reading failures

- Test output is long. To find layout errors, filter it:
  `flutter.bat test 2>&1 | grep -E "overflowed|error-causing|lib/.*dart:[0-9]+|All tests passed|Some tests failed" | grep -v packages/flutter/`
- `RenderFlex overflowed` means a `Row` or `Column` child can't shrink. Wrap the text in `Expanded` or `Flexible` with `TextOverflow.ellipsis`. Don't just change the test viewport.
- If `pumpAndSettle` times out, it's because the status dots animate forever. Use `pump(const Duration(milliseconds: ...))` instead.
- "A Timer is still pending" means a test built a `MockAgentBackend` with simulation on. Use `simulate: false, latency: Duration.zero`.

Report the result briefly: which steps passed, plus any remaining failures with their `file:line`.
