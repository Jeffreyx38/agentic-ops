---
name: Auto-fix escalation
about: Created by Claude Code when it detects an unfixable CI failure
title: "[needs-human] CI failure on PR #<PR> — <error type>"
labels: ["needs-human", "no-autofix"]
---

## CI failure requiring human intervention

**PR:** #
**Error type:**

### Evidence from CI logs
```
<paste relevant log snippet>
```

### Why it cannot be auto-fixed

### Required action
- [ ] Fix the root cause
- [ ] Remove the `no-autofix` label from the PR
- [ ] Re-run CI

---
*Created by the Claude Code auto-fix workflow.*
