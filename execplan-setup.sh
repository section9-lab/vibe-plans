#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
PROJECT_NAME="open-exec-plans"
MANAGED_MARKER="open-exec-plans:managed"
BRIDGE_MARKER="open-exec-plans:bridge"

DRY_RUN=0
FORCE_MANAGED=0
PRINT_PROFILE=0
INSTALL_ALL=0

ALL_TOOLS=(codex claude gemini opencode copilot)
REQUESTED_TOOLS=()

CREATED_FILES=()
UPDATED_FILES=()
APPENDED_FILES=()
SKIPPED_FILES=()
WARNINGS=()

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options] [tool ...]

OpenExecPlans installs an ExecPlan-first workflow into the current repository.
It always ensures the canonical source exists.

Default behavior:
  Running without tool arguments installs bridges for all supported tools.
  Passing one or more tool names installs only those tool bridges.

Options:
  --tool <list>         Comma-separated tools: codex, claude, gemini, opencode, copilot
  --all                 Install bridges for all supported tools (same as default)
  --dry-run             Show planned file operations without writing files
  --force-managed       Overwrite managed bridge/config files that do not support in-file markers
  --print-profile       Print the selected tools and target files before applying changes
  -h, --help            Show this help text

Legacy shorthand:
  $SCRIPT_NAME claude
  $SCRIPT_NAME codex opencode

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME claude
  $SCRIPT_NAME --tool claude,gemini
  $SCRIPT_NAME --all --dry-run
EOF
}

timestamp() {
  date '+%H:%M:%S'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

warn() {
  WARNINGS+=("$*")
  printf '[%s] warning: %s\n' "$(timestamp)" "$*" >&2
}

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

append_unique_tool() {
  local tool="$1"
  if [[ "${#REQUESTED_TOOLS[@]}" -eq 0 ]] || ! contains "$tool" "${REQUESTED_TOOLS[@]}"; then
    REQUESTED_TOOLS+=("$tool")
  fi
}

validate_tool() {
  local tool="$1"
  if contains "$tool" "${ALL_TOOLS[@]}"; then
    return 0
  fi
  echo "Unsupported tool: $tool" >&2
  usage
  exit 1
}

parse_tool_list() {
  local csv="$1"
  local old_ifs="$IFS"
  local part
  IFS=','
  for part in $csv; do
    IFS="$old_ifs"
    if [[ -z "$part" ]]; then
      continue
    fi
    if [[ "$part" == "all" ]]; then
      INSTALL_ALL=1
      continue
    fi
    validate_tool "$part"
    append_unique_tool "$part"
    IFS=','
  done
  IFS="$old_ifs"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tool|-t)
        if [[ $# -lt 2 ]]; then
          echo "Missing value for $1" >&2
          usage
          exit 1
        fi
        parse_tool_list "$2"
        shift 2
        ;;
      --all)
        INSTALL_ALL=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --force-managed)
        FORCE_MANAGED=1
        shift
        ;;
      --print-profile)
        PRINT_PROFILE=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      codex|claude|gemini|opencode|copilot)
        append_unique_tool "$1"
        shift
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ "$INSTALL_ALL" -eq 1 ]]; then
    REQUESTED_TOOLS=("${ALL_TOOLS[@]}")
  fi

  if [[ "${#REQUESTED_TOOLS[@]}" -eq 0 ]]; then
    REQUESTED_TOOLS=("${ALL_TOOLS[@]}")
  fi
}

ensure_dir() {
  local dir="$1"
  if [[ -z "$dir" || "$dir" == "." ]]; then
    return
  fi
  if [[ -d "$dir" ]]; then
    return
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "mkdir -p $dir"
    return
  fi
  mkdir -p "$dir"
}

managed_marker_for() {
  local path="$1"
  case "$path" in
    *.md) echo "<!-- $MANAGED_MARKER -->" ;;
    *.toml|*.sh) echo "# $MANAGED_MARKER" ;;
    *) echo "" ;;
  esac
}

path_supports_force_overwrite() {
  local path="$1"
  case "$path" in
    .claude/settings.json|opencode.json) return 0 ;;
    *) return 1 ;;
  esac
}

write_content() {
  local path="$1"
  local content="$2"
  local dir
  dir="$(dirname "$path")"
  ensure_dir "$dir"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "write $path"
    return
  fi

  printf '%s\n' "$content" > "$path"
}

record_created() {
  CREATED_FILES+=("$1")
}

record_updated() {
  UPDATED_FILES+=("$1")
}

record_appended() {
  APPENDED_FILES+=("$1")
}

record_skipped() {
  SKIPPED_FILES+=("$1")
}

write_or_update_file() {
  local path="$1"
  local content="$2"
  local marker
  marker="$(managed_marker_for "$path")"

  if [[ ! -f "$path" ]]; then
    write_content "$path" "$content"
    record_created "$path"
    return
  fi

  if [[ "$(cat "$path")" == "$content" ]]; then
    record_skipped "$path (unchanged)"
    return
  fi

  if [[ -n "$marker" ]] && grep -Fq "$marker" "$path"; then
    write_content "$path" "$content"
    record_updated "$path"
    return
  fi

  if [[ "$FORCE_MANAGED" -eq 1 ]] && path_supports_force_overwrite "$path"; then
    write_content "$path" "$content"
    record_updated "$path"
    return
  fi

  record_skipped "$path (existing unmanaged file)"
}

append_to_existing_file() {
  local path="$1"
  local block="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "append $path"
    record_appended "$path"
    return
  fi
  printf '\n%s\n' "$block" >> "$path"
  record_appended "$path"
}

render_agents_md() {
  cat <<EOF
<!-- $MANAGED_MARKER -->
# Project Instructions

This repository is ExecPlan-first.

## Canonical Source

- \`AGENTS.md\` is the canonical project entrypoint.
- \`.agents/PLANS.md\` is the canonical ExecPlan specification.
- Store plan files in \`.agents/exec-plans/\`.

## Workflow

- For multi-step work, significant refactors, or any task where design decisions materially affect implementation, create or update an ExecPlan before code edits.
- If your tool supports a native plans directory or equivalent, point it at \`.agents/exec-plans/\`.
- If your tool does not provide a native planning entrypoint, use the \`brainstorming\` skill in \`.agents/skills/brainstorming/SKILL.md\` before implementation.
- Keep tool-specific bridge files short. They should direct the tool back to this canonical source instead of duplicating the entire workflow.
EOF
}

render_agents_bridge_append() {
  cat <<EOF
<!-- $BRIDGE_MARKER -->
## OpenExecPlans Bridge

- Canonical ExecPlan rules live in \`.agents/PLANS.md\`.
- Store plan files in \`.agents/exec-plans/\`.
- If this tool does not provide a native planning directory, use the \`brainstorming\` skill in \`.agents/skills/brainstorming/SKILL.md\` before implementation.
EOF
}

render_plans_md() {
  cat <<EOF
<!-- $MANAGED_MARKER -->
# ExecPlans

Use ExecPlans for complex features, significant refactors, and any multi-step task where design choices matter.

Repository convention: store ExecPlan files in \`.agents/exec-plans/\` using date-prefixed names such as \`.agents/exec-plans/2026-04-22-add-checker.md\`.

If a plan is first produced inline in chat, materialize it in \`.agents/exec-plans/\` before repository code edits.

## Requirements

Every ExecPlan must:

- Explain the user-visible purpose of the work.
- Be self-contained enough that a new contributor can continue from the plan and working tree.
- Be maintained as a living document.
- Include concrete file paths, validation steps, and decisions.

## Required Sections

- \`Purpose / Big Picture\`
- \`Progress\`
- \`Surprises & Discoveries\`
- \`Decision Log\`
- \`Outcomes & Retrospective\`
- \`Context and Orientation\`
- \`Plan of Work\`
- \`Concrete Steps\`
- \`Validation and Acceptance\`
- \`Idempotence and Recovery\`
- \`Artifacts and Notes\`
- \`Interfaces and Dependencies\`

## Skeleton

\`\`\`md
# <Short action-oriented title>

This ExecPlan is a living document. Keep \`Progress\`, \`Surprises & Discoveries\`, \`Decision Log\`, and \`Outcomes & Retrospective\` current as work proceeds.

This plan follows \`.agents/PLANS.md\`.

## Purpose / Big Picture

Explain what changes for users or contributors after the work lands.

## Progress

- [ ] Create or update this plan before code edits.
- [ ] Implement the planned work.
- [ ] Validate the result.

## Surprises & Discoveries

- Observation:
  Evidence:

## Decision Log

- Decision:
  Rationale:
  Date/Author:

## Outcomes & Retrospective

Summarize shipped behavior, remaining gaps, and lessons learned.

## Context and Orientation

Describe the current repository state and key files.

## Plan of Work

Describe the sequence of edits in prose.

## Concrete Steps

List exact commands to run from the repository root.

## Validation and Acceptance

Describe observable pass criteria.

## Idempotence and Recovery

Explain safe reruns and rollback expectations.

## Artifacts and Notes

Keep short evidence snippets here.

## Interfaces and Dependencies

Describe touched interfaces, config files, and external tool assumptions.
\`\`\`
EOF
}

render_execplans_readme() {
  cat <<EOF
<!-- $MANAGED_MARKER -->
# ExecPlan Directory

This is the canonical directory for ExecPlan files in this repository.

Use date-prefixed file names:

- \`.agents/exec-plans/YYYY-MM-DD-<topic>.md\`

When a plan starts in chat first, materialize it here before code edits.
EOF
}

render_brainstorming_skill() {
  cat <<EOF
---
name: brainstorming
description: "Use this before implementation when a task needs design clarification or when your tool lacks a native plans directory."
---
<!-- $MANAGED_MARKER -->

# Brainstorming Ideas Into Designs

Use this skill before implementation when the task involves design choices, unclear requirements, or a tool workflow that lacks a native plan directory.

## Goals

- Understand the current project context before proposing implementation.
- Ask one focused clarification question at a time when information is missing.
- Present two or three approaches with trade-offs when there is more than one reasonable path.
- Get explicit user approval before implementation starts.

## Workflow

1. Inspect the current repository state first.
2. Clarify the goal and constraints.
3. Present a concise recommended design.
4. After approval, create or update an ExecPlan in \`.agents/exec-plans/\`.
5. Implement against that ExecPlan.

## Output Expectations

- Keep questions narrow and sequential.
- Prefer multiple choice when it reduces effort for the user.
- Do not write code before the design is accepted.
- When the design is accepted, point back to \`.agents/PLANS.md\` and the canonical plan directory.
EOF
}

render_claude_md() {
  cat <<EOF
<!-- $MANAGED_MARKER -->
# Claude Code Bridge

This repository is ExecPlan-first.

- Canonical workflow rules live in \`AGENTS.md\`.
- Canonical ExecPlan rules live in \`.agents/PLANS.md\`.
- Store plan files in \`.agents/exec-plans/\`.

Project Claude settings should point \`plansDirectory\` at \`.agents/exec-plans\`.
EOF
}

render_claude_settings_json() {
  cat <<EOF
{
  "plansDirectory": ".agents/exec-plans"
}
EOF
}

render_codex_config_toml() {
  cat <<EOF
# $MANAGED_MARKER
developer_instructions = """
This repository is ExecPlan-first.

Canonical source files:
- AGENTS.md
- .agents/PLANS.md
- .agents/exec-plans/

If work is multi-step or design-sensitive, create or update an ExecPlan in .agents/exec-plans/ before code changes.
If the environment lacks a native planning directory, use the brainstorming skill in .agents/skills/brainstorming/SKILL.md before implementation.
"""

[features]
collaboration_modes = true
EOF
}

render_gemini_md() {
  cat <<EOF
<!-- $MANAGED_MARKER -->
# Gemini Bridge

This repository is ExecPlan-first.

- Read \`AGENTS.md\` as the canonical project entrypoint.
- Read \`.agents/PLANS.md\` for the full ExecPlan workflow.
- Store plan files in \`.agents/exec-plans/\`.
- Use the \`brainstorming\` skill in \`.agents/skills/brainstorming/SKILL.md\` before implementation when design work is needed.
EOF
}

render_opencode_json() {
  cat <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "instructions": ["AGENTS.md", ".agents/PLANS.md"]
}
EOF
}

render_copilot_instructions_md() {
  cat <<EOF
<!-- $MANAGED_MARKER -->
# Copilot Agent Bridge

This repository is ExecPlan-first.

- Canonical workflow rules live in \`AGENTS.md\`.
- Canonical ExecPlan rules live in \`.agents/PLANS.md\`.
- Store plan files in \`.agents/exec-plans/\`.
- For multi-step work, create or update an ExecPlan before code edits.
- If planning help is needed, follow the design-first workflow described in the \`brainstorming\` skill at \`.agents/skills/brainstorming/SKILL.md\`.
EOF
}

list_target_files_for_tool() {
  local tool="$1"
  case "$tool" in
    codex)
      echo ".codex/config.toml"
      ;;
    claude)
      echo "CLAUDE.md .claude/settings.json"
      ;;
    gemini)
      echo "GEMINI.md"
      ;;
    opencode)
      echo "opencode.json"
      ;;
    copilot)
      echo ".github/copilot-instructions.md"
      ;;
  esac
}

print_profile() {
  local tool
  local files
  echo "Selected tools: ${REQUESTED_TOOLS[*]}"
  echo "Canonical files:"
  echo "  - AGENTS.md"
  echo "  - .agents/PLANS.md"
  echo "  - .agents/exec-plans/README.md"
  echo "  - .agents/skills/brainstorming/SKILL.md"
  echo "Tool bridge files:"
  for tool in "${REQUESTED_TOOLS[@]}"; do
    files="$(list_target_files_for_tool "$tool")"
    if [[ -n "$files" ]]; then
      echo "  - [$tool] $files"
    fi
  done
}

install_agents_md() {
  local path="AGENTS.md"
  local bridge_block
  local desired
  bridge_block="$(render_agents_bridge_append)"
  desired="$(render_agents_md)"

  if [[ ! -f "$path" ]]; then
    write_content "$path" "$desired"
    record_created "$path"
    return
  fi

  if [[ "$(cat "$path")" == "$desired" ]]; then
    record_skipped "$path (unchanged)"
    return
  fi

  if grep -Fq "<!-- $MANAGED_MARKER -->" "$path"; then
    write_content "$path" "$desired"
    record_updated "$path"
    return
  fi

  if grep -Fq "$BRIDGE_MARKER" "$path" || grep -Fq ".agents/PLANS.md" "$path"; then
    record_skipped "$path (existing unmanaged file already references ExecPlans)"
    return
  fi

  append_to_existing_file "$path" "$bridge_block"
}

install_canonical_files() {
  install_agents_md
  write_or_update_file ".agents/PLANS.md" "$(render_plans_md)"
  write_or_update_file ".agents/exec-plans/README.md" "$(render_execplans_readme)"
  write_or_update_file ".agents/skills/brainstorming/SKILL.md" "$(render_brainstorming_skill)"
}

install_tool_codex() {
  write_or_update_file ".codex/config.toml" "$(render_codex_config_toml)"
}

install_tool_claude() {
  write_or_update_file "CLAUDE.md" "$(render_claude_md)"
  write_or_update_file ".claude/settings.json" "$(render_claude_settings_json)"
}

install_tool_gemini() {
  write_or_update_file "GEMINI.md" "$(render_gemini_md)"
}

install_tool_opencode() {
  write_or_update_file "opencode.json" "$(render_opencode_json)"
}

install_tool_copilot() {
  write_or_update_file ".github/copilot-instructions.md" "$(render_copilot_instructions_md)"
}

install_tool() {
  local tool="$1"
  case "$tool" in
    codex) install_tool_codex ;;
    claude) install_tool_claude ;;
    gemini) install_tool_gemini ;;
    opencode) install_tool_opencode ;;
    copilot) install_tool_copilot ;;
  esac
}

print_summary() {
  local file

  echo
  log "Summary"

  if [[ "${#CREATED_FILES[@]}" -gt 0 ]]; then
    echo "Created:"
    for file in "${CREATED_FILES[@]}"; do
      echo "  - $file"
    done
  fi

  if [[ "${#UPDATED_FILES[@]}" -gt 0 ]]; then
    echo "Updated:"
    for file in "${UPDATED_FILES[@]}"; do
      echo "  - $file"
    done
  fi

  if [[ "${#APPENDED_FILES[@]}" -gt 0 ]]; then
    echo "Appended:"
    for file in "${APPENDED_FILES[@]}"; do
      echo "  - $file"
    done
  fi

  if [[ "${#SKIPPED_FILES[@]}" -gt 0 ]]; then
    echo "Skipped:"
    for file in "${SKIPPED_FILES[@]}"; do
      echo "  - $file"
    done
  fi

  if [[ "${#WARNINGS[@]}" -gt 0 ]]; then
    echo "Warnings:"
    for file in "${WARNINGS[@]}"; do
      echo "  - $file"
    done
  fi
}

main() {
  parse_args "$@"

  if [[ "$PRINT_PROFILE" -eq 1 ]]; then
    print_profile
    if [[ "$DRY_RUN" -eq 1 ]]; then
      exit 0
    fi
  fi

  log "Installing canonical ExecPlan workflow"
  install_canonical_files

  local tool
  for tool in "${REQUESTED_TOOLS[@]}"; do
    log "Installing bridge for $tool"
    install_tool "$tool"
  done

  print_summary
}

main "$@"
