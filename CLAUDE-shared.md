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

## Frontend conventions
- Keep route files thin
- Organize frontend code by feature
- Keep reusable primitives in shared areas only when truly shared

## Workflow
- GitHub Issues define the work
- Claude implements approved issues
- Pull requests are reviewed by a human before merge
