# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

emdash is an Electron desktop app for macOS that orchestrates multiple coding agents (Codex CLI, Claude Code CLI, Droid/Factory CLI) in parallel using Git worktrees for isolation. Each agent workspace runs in its own worktree branch, enabling concurrent development tasks without interference.

**Key Architecture:**
- **Main Process** (`src/main/`): Electron backend with IPC handlers, services (Git, worktrees, agents, database), and native integration (node-pty, SQLite)
- **Renderer Process** (`src/renderer/`): React + Vite frontend with real-time streaming chat UI, workspace management, and PR creation
- **Data Layer**: SQLite for persistence (projects, workspaces, conversations, messages) + streaming logs written to OS userData folder
- **Process Management**: Child processes spawned for agent CLIs, PTY terminals, Git operations

## Development Commands

### Primary Workflows

```bash
# Development (concurrent main + renderer processes)
npm run dev

# Type checking (run before commits)
npm run type-check

# Linting
npm run lint

# Production build
npm run build

# Package for distribution (macOS)
npm run package
```

### Development Details

- **Renderer hot-reloads** automatically (Vite)
- **Main process changes** require restarting the dev app (Ctrl+C, then `npm run dev`)
- **After dependency changes** involving native modules (sqlite3, node-pty, keytar): run `npm run postinstall` to rebuild for Electron

## Architecture Details

### Git Worktrees & Branch Isolation

Each workspace operates in a Git worktree created **outside** the main repository:
- Worktrees live in `../worktrees/` (sibling to project root)
- Branch naming: `agent/{workspace-name}-{timestamp}-{random}`
- Initial branch push sets upstream tracking automatically for PR workflows
- **Never delete worktree folders manually** — use `git worktree prune` or in-app removal

**Key service:** `WorktreeService.ts`
- `createWorktree()`: Creates branch + worktree, pushes to origin with upstream
- `removeWorktree()`: Cleans up worktree directory and deletes branch
- Auto-ignores `codex-stream.log` in each worktree's `.git/info/exclude`

### Agent Streaming & Process Management

**CodexService** (`CodexService.ts`):
- Spawns `codex exec --sandbox workspace-write <message>` as child process
- Streams stdout/stderr to logs and emits events: `codex:output`, `codex:error`, `codex:complete`
- Logs stored in `{userData}/logs/codex/{workspaceId}/codex-stream.log`
- Supports stopping streams via SIGINT/SIGTERM
- Persists final agent message to DB on stream completion

**AgentService** (`AgentService.ts`):
- Multi-provider orchestration (codex, claude)
- Claude support: Tries SDK first (`@anthropic/claude-code-sdk`), falls back to CLI with `--output-format stream-json`
- Safe edit tool allowlist: `Edit`, `MultiEdit`, `Write`, `Read` only
- Ensures only **one process per workspace** across all providers

**Stream Log Parsing:**
- Frontend displays real-time tail from log files
- Header format: `=== Codex Stream {ISO_TIMESTAMP} ===`
- UI extracts content after `--- Output ---` marker

### Database Schema (SQLite)

**Location:** `{userData}/emdash.db` (legacy names auto-migrated: `database.sqlite`, `orcbench.db`)

**Tables:**
- `projects`: Repository metadata, Git remote/branch, GitHub connection status
- `workspaces`: Worktree metadata (path, branch, status, agent_id)
- `conversations`: Chat sessions per workspace
- `messages`: User and agent messages with metadata (JSON string)

**Foreign key cascades:** Deleting a project removes associated workspaces → conversations → messages

### IPC Communication

**Handler patterns:**
- `src/main/ipc/*.ts`: IPC handlers grouped by domain (agent, project, worktree, git, github, db)
- All handlers exposed via `contextBridge` in `preload.ts`
- Renderer calls via `window.ipc.invoke('channel', params)`

**Critical channels:**
- `agent:start-stream`, `agent:stop-stream`: Agent process control
- `worktree:create`, `worktree:remove`: Workspace lifecycle
- `db:save-message`, `db:get-messages`: Conversation persistence
- `github:create-pr`: PR creation via GitHub CLI (`gh`)

### Provider CLI Requirements

**Codex (primary):**
```bash
npm install -g @openai/codex
# or
brew install codex
codex  # authenticate
```

**Claude Code (optional):**
```bash
npm install -g @anthropic-ai/claude-code
claude
/login  # in CLI
```

**GitHub CLI (optional, for PR features):**
```bash
brew install gh
gh auth login
```

### Streaming UI & Renderer Conventions

**Message rendering** (`MessageList.tsx`, `ai-elements/response.tsx`):
- "Reasoning" content renders in collapsible sections
- Response content shown after `codex` marker appears in stream
- Partial messages displayed during active streams
- Syntax highlighting via `react-syntax-highlighter`

**State management:**
- Local React state + IPC events for real-time updates
- `useCodexStream` hook: Subscribes to `codex:output`, `codex:error`, `codex:complete`
- `useFileChanges` hook: Polls Git status for uncommitted changes

### Critical Development Patterns

**Electron Main Process:**
- Use `execFile` over `exec` to avoid shell quoting issues
- Never write logs to worktree directories (use `app.getPath('userData')`)
- Spawn child processes with explicit `cwd` and environment
- Clean up child processes on app quit

**Native Modules:**
- `node-pty`: Terminal emulation for PTY sessions
- `sqlite3`: Database backend (auto-rebuilt for Electron via `electron-rebuild`)
- `keytar`: Secure credential storage (unused currently, but linked)

**TypeScript Configuration:**
- **Main process:** CommonJS modules (`tsconfig.main.json`), output to `dist/main/`
- **Renderer:** ESNext modules (`tsconfig.json`), bundled by Vite
- Shared types in `src/types/` and `src/renderer/types/`

## Common Development Scenarios

### Adding a New Agent Provider

1. Update `ProviderId` type in `AgentService.ts`
2. Implement installation check in `isInstalled()`
3. Add streaming logic in `startStream()` (spawn process, parse output, emit events)
4. Wire up IPC handlers in `agentIpc.ts` if needed
5. Update UI provider selector in `ChatInput.tsx`

### Debugging Stream Issues

1. Check agent logs: `{userData}/logs/{provider}/{workspaceId}/stream.log`
2. Verify child process spawn in main process console
3. Inspect IPC events in renderer DevTools console
4. Confirm Git worktree exists and is on correct branch

### Resetting Database

```bash
# Quit app first
rm -f "$HOME/Library/Application Support/emdash/emdash.db"*
rm -f "$HOME/Library/Application Support/Electron/emdash.db"*  # dev mode
# App recreates schema on next launch
```

## Testing & Verification

**Before committing:**
```bash
npm run type-check  # Must pass
npm run lint         # Address warnings
npm run build        # Verify production build
```

**End-to-end smoke test:**
1. Start app (`npm run dev`)
2. Open a project with a Git repository
3. Create a workspace → verify worktree creation
4. Send a message to Codex/Claude → verify stream output
5. Check file changes panel → verify Git status updates
6. Create a PR → verify GitHub CLI integration

## Commit Conventions

Use Conventional Commits format:
- `feat(scope):` – new functionality
- `fix(scope):` – bug fix
- `refactor:`, `chore:`, `docs:`, `perf:`, `test:` – other changes

Examples:
```
feat(agents): add gemini provider support
fix(worktree): handle spaces in branch names
refactor(db): consolidate message persistence
```
