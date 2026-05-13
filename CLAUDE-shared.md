# Domiva Shared Conventions

This file is the single source of truth for conventions shared across all Domiva repos.
- Locally: referenced via `@` import in each repo's `CLAUDE.md`
- CI: fetched from `Domiva-Life/domiva-workflows` by each agent workflow before Claude runs

Architectural decisions about the agent infrastructure are documented in `docs/adr/` in the `domiva-workflows` repo. If you are modifying CI workflows or agent behavior, read those ADRs first.

## Agent behavior
Agents must:
- work only on the assigned issue
- keep changes small and reviewable
- avoid unrelated refactors
- follow existing project structure
- add or update tests when behavior changes

Agents must not:
- introduce new frameworks without explicit instruction
- modify hidden or unrelated files
- change infrastructure or deployment behavior unless explicitly requested

## Documentation conventions

### Inline comments
For any non-obvious logic, comments explain both **what** the code does and **why** it was written that way — especially when a fix or workaround was required:
- What: describe the behavior so the next reader can reason about changing it
- Why: document the constraint, bug, or framework behavior that required this approach
- Flag what would break if this code were changed or removed
- If introduced or changed by an automated fix agent, note that and the reason

Example of a useful comment:
```java
// Permits Spring's internal error dispatch to pass through security unchanged.
// Without this, container error dispatches (e.g. triggered by sendError()) are
// intercepted by the security filter chain and return 401 instead of the intended
// error status. Note: adding /error to auth-excludes is NOT sufficient — MvcRequestMatcher
// only matches REQUEST dispatcher type, not ERROR dispatcher type.
.dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
```

### Architecture Decision Records (ADRs)
Use ADRs for decisions that are cross-cutting, non-obvious from the code alone, or likely to be revisited. Store in `docs/adr/NNN-short-title.md`:

```markdown
# NNN. Short Title

**Status**: Accepted
**Date**: YYYY-MM-DD

## Context
What problem or constraint prompted this decision?

## Decision
What was decided?

## Consequences
What does this enable or constrain going forward?
```

Create an ADR when:
- A framework/library workaround was required (and the "obvious" approach doesn't work)
- A dependency was intentionally excluded or deferred
- A design pattern was chosen over a more common alternative
- A security or data model constraint was established

## Backend conventions
- Use descriptive variable names
- Write useful code comments explaining both what the code does and why
- Prefer UUID identifiers for entities
- Keep domain logic organized and modular
- Use `Instant` for all timestamp fields and `TIMESTAMPTZ` for all timestamp columns in migrations — never `LocalDateTime` or `TIMESTAMP` (see ADR 002)

### Database migrations

**Before creating any migration file**, inspect the existing migrations to determine the correct version number. Never use a version number from the issue description — it may be stale by the time the issue is implemented.

Required check (coding agent and fix agent both must do this before finishing):
```
ls api/src/main/resources/db/migration/
```
Find the highest existing `VN__*.sql` filename. Your new migration must be `V(N+1)__description.sql`.

- Never create a migration with a version that already exists — Flyway will refuse to start
- Never modify an existing migration file — create a new one instead
- If the issue specifies a version number, treat it as a hint only; always verify against the actual files

## Frontend conventions
- Keep route files thin
- Organize frontend code by feature
- Keep reusable primitives in shared areas only when truly shared

## Workflow
- GitHub Issues define the work
- Claude implements approved issues
- Pull requests are reviewed by a human before merge

## Agent Learnings

The files appended below this section (added by the workflow at runtime) record mistakes
observed and corrected by Fix Agents across all Domiva repos. They are fetched from
`Domiva-Life/domiva-workflows/agent-learnings/` and appended to this file before you run.

**Read them.** They represent hard-won corrections — patterns the Coding Agent got wrong
that required a Fix Agent to clean up. Each entry is a mistake made once so it never
needs to be made again.

**Priority order — learnings never override these:**
1. ADRs in `docs/adr/` — authoritative architectural decisions, always take precedence
2. CLAUDE.md conventions — project rules set by humans
3. Agent learnings — observed mistake patterns, complementary to the above

If a learning appears to conflict with an ADR or CLAUDE.md, follow the ADR or CLAUDE.md.
If a learning rises to the level of an architectural decision, it should become an ADR —
not stay as a learning entry.

**Write to them** when you fix a recurring implementation mistake. If the pattern belongs
to the language/framework (Java, Flutter, Node, TypeScript, etc.), write to the
stack-specific file (e.g. `agent-learnings/java.md`, `agent-learnings/node.md`). If no
file yet exists for the stack, create it following the same format as `cross-repo.md`.
If the pattern applies broadly regardless of language, write to `cross-repo.md`. The write
pattern and API command are documented at the top of each file.
