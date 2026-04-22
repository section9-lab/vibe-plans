<div align="center">
  <h1 align="center">OpenExecPlans</h1>
</div>

OpenExecPlans is a single-file Bash bootstrapper that installs an ExecPlan-first workflow into repositories that use different vibe coding tools.

## Quick Start: Claude Code

Use this when you want Claude Code to plan larger work in `.agents/exec-plans/` before it edits code.

1. Install the Claude bridge from the root of your repository:

```sh
curl -fsSL https://raw.githubusercontent.com/jackwang/open-exec-plans/main/execplan-setup.sh | bash -s -- claude
```

This creates or updates the shared ExecPlan files plus Claude-specific files:

- `AGENTS.md`
- `.agents/PLANS.md`
- `.agents/exec-plans/`
- `CLAUDE.md`
- `.claude/settings.json`

2. Open Claude Code in that repository.

Claude will read `CLAUDE.md`, and `.claude/settings.json` points its `plansDirectory` at `.agents/exec-plans`.

3. Ask Claude to start from an ExecPlan for non-trivial work:

```text
Please add email/password login. Start by creating an ExecPlan, ask me any important design questions first, then implement after the plan is clear.
```

4. Review the plan Claude creates in `.agents/exec-plans/`, then continue with:

```text
The plan looks good. Follow it, keep the Progress and Decision Log sections updated, and validate the result before finishing.
```

For quick tasks, you can still ask Claude to edit directly. OpenExecPlans is most useful for multi-step features, refactors, migrations, and work where design decisions matter.

The setup is safe to rerun. Managed OpenExecPlans files are refreshed, and existing unmanaged Claude files are left alone by default.

It creates one canonical source of truth based on:

- `AGENTS.md`
- `.agents/PLANS.md`
- `.agents/exec-plans/`
- `.agents/skills/brainstorming/SKILL.md`

Then it adds tool-native bridge files such as `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`, `.codex/config.toml`, and `.claude/settings.json`.

## What It Does

OpenExecPlans follows a hybrid model:

- Canonical source first: shared workflow rules live in `AGENTS.md` and `.agents/*`
- Native bridge second: each tool gets its preferred entrypoint when useful
- Brainstorming fallback: tools without a native plans directory still get a `brainstorming` skill to enforce a design-first workflow

This keeps one central ExecPlan system while still meeting each tool where it works best.

## Supported Tools

- `codex`
- `claude`
- `gemini`
- `opencode`
- `copilot`

Notes:

- Claude currently gets the strongest native planning support through `.claude/settings.json` with `plansDirectory` pointing to `.agents/exec-plans`.
- Tools without native planning directories rely on the canonical workflow plus the `brainstorming` skill.

## Install

Default: install the canonical source plus all supported bridge files.

```sh
curl -fsSL https://raw.githubusercontent.com/jackwang/open-exec-plans/main/execplan-setup.sh | bash
```

Install specific tools only by passing tool names or `--tool`:

```sh
curl -fsSL https://raw.githubusercontent.com/jackwang/open-exec-plans/main/execplan-setup.sh | bash -s -- claude
curl -fsSL https://raw.githubusercontent.com/jackwang/open-exec-plans/main/execplan-setup.sh | bash -s -- --tool claude,gemini
```

Install all bridges explicitly:

```sh
curl -fsSL https://raw.githubusercontent.com/jackwang/open-exec-plans/main/execplan-setup.sh | bash -s -- --all
```

Preview changes without writing files:

```sh
curl -fsSL https://raw.githubusercontent.com/jackwang/open-exec-plans/main/execplan-setup.sh | bash -s -- --all --dry-run --print-profile
```

## Generated Files

Canonical source:

- `AGENTS.md`
- `.agents/PLANS.md`
- `.agents/exec-plans/README.md`
- `.agents/skills/brainstorming/SKILL.md`

Tool bridges and config:

- Codex: `.codex/config.toml`
- Claude Code: `CLAUDE.md`, `.claude/settings.json`
- Gemini CLI: `GEMINI.md`
- OpenCode: `opencode.json`
- Copilot: `.github/copilot-instructions.md`

## Command Line UX

Run locally:

```sh
./execplan-setup.sh
./execplan-setup.sh claude
./execplan-setup.sh --tool claude
./execplan-setup.sh --tool codex,opencode,copilot
./execplan-setup.sh --all --dry-run
./execplan-setup.sh --all --force-managed
```

Options:

- `--tool <list>`: comma-separated tool names; installs only those tool bridges
- `--all`: install all supported tool bridges, which is also the no-argument default
- `--dry-run`: print planned writes without modifying files
- `--force-managed`: overwrite managed config files that do not support inline markers
- `--print-profile`: print the selected target files before applying changes

Legacy shorthand still works:

```sh
./execplan-setup.sh claude
./execplan-setup.sh codex
```

## Safety and Idempotence

The script is conservative by default.

- Managed Markdown and TOML files are refreshed when they still contain the OpenExecPlans managed marker.
- Existing unmanaged files are left alone.
- `AGENTS.md` is treated specially: if it already exists and is not managed by OpenExecPlans, the script appends a small bridge block instead of replacing the file.
- JSON config files are only overwritten with `--force-managed`.

## Compatibility Notes

- Cursor users should choose the bridge that matches their active engine, usually Claude or Codex.
- OpenCode already understands `AGENTS.md` and `.agents/skills/*`, so its generated `opencode.json` is intentionally small.
- Copilot supports repository instructions in `.github/copilot-instructions.md`, but the canonical workflow still lives in `AGENTS.md` and `.agents/PLANS.md`.
- Gemini CLI prefers `GEMINI.md`, but this project still treats `AGENTS.md` as canonical.

## Why the Brainstorming Skill Exists

Some tools do not have a native `plansDirectory`-style feature. For those tools, a short bridge file alone is not enough to reliably enforce a design-first workflow. The `brainstorming` skill fills that gap by telling the agent to:

- inspect the repository first
- ask focused clarification questions
- propose design options
- wait for approval
- only then create or update an ExecPlan and start implementation

## Reference

- [OpenAI Exec Plans article](https://developers.openai.com/cookbook/articles/codex_exec_plans)

## License

MIT
