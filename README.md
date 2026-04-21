# vibe-plans

## use

This script is idempotent: if AGENTS.md or .agent/template/PLAN.md already exist, they will be left unchanged.


**defult**
```sh
curl -fsSL https://raw.githubusercontent.com/section9-lab/vibe-plans/main/execplan-setup.sh | bash
```

**Codex**
```sh
curl -fsSL https://raw.githubusercontent.com/section9-lab/vibe-plans/main/execplan-setup.sh | bash -s -- codex
```

**Cursor**
```sh
curl -fsSL https://raw.githubusercontent.com/section9-lab/vibe-plans/main/execplan-setup.sh | bash -s -- cursor
```

**Claude Code**
```sh
curl -fsSL https://raw.githubusercontent.com/section9-lab/vibe-plans/main/execplan-setup.sh | bash -s -- claude
```

**OpenCode**
```sh
curl -fsSL https://raw.githubusercontent.com/section9-lab/vibe-plans/main/execplan-setup.sh | bash -s -- opencode
```

**Copilot-CLI**
```sh
curl -fsSL https://raw.githubusercontent.com/section9-lab/vibe-plans/main/execplan-setup.sh | bash -s -- copilot
```
---
## ref
[exec_plans](https://developers.openai.com/cookbook/articles/codex_exec_plans)
