# CLAUDE.md

@AGENTS.md

## Claude Code specifics

- **Skills** (`.claude/skills/`):
  - `verify`: format, analyze and test with the full Flutter paths.
  - `add-screen`: add a tab or detail screen with routing and a smoke-test entry.
  - `add-backend-operation`: add a backend action end to end (contract, mock, provider, UI).
- **Subagents** (`.claude/agents/`):
  - `flutter-screen-builder`: builds one screen area with strict file ownership, which makes it safe to run in parallel.
  - `mobile-ui-reviewer`: a read-only review of mobile UX and layout issues.
- **Parallel work:**
  - Build shared contracts first (models, backend methods, providers, shared widgets, sheet function signatures as stubs). Then fan out `flutter-screen-builder` agents, each owning a disjoint set of files.
  - Subagents never commit. The main session commits each agent's files as a separate commit after running a full `flutter analyze`.
- Keep token use proportionate. Don't re-run the analyzer or tests without a code change in between, and don't build APKs unless asked.
