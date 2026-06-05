# Agent Learnings

This directory contains distilled patterns that agents read at the start of every run. Think of them as institutional memory — mistakes made once, captured so they're never made again.

## Files

| File | Scope |
|---|---|
| `cross-repo.md` | Patterns that apply across all stacks and repos |
| `java.md` | Java/Spring Boot specific patterns |
| `flutter.md` | Flutter/Dart specific patterns |

## How entries get here

**Manually (today):** When a Fix Agent has to correct something the Coding Agent got wrong, a learning should be added here so the Coding Agent doesn't make the same mistake again.

**Automatically (planned):** A daily synthesis job will read raw learnings submitted by customer agent runs, distill them into reusable patterns by language and category, and promote the best ones into these files. This closes the loop — every customer agent run makes every agent smarter.

## What belongs here

Patterns that are:
- Reusable across many situations (not one-off fixes)
- Related to coding, architecture, or framework behavior
- Non-obvious enough that an agent would reasonably get it wrong again

Not business logic, customer-specific patterns, or anything that would only apply to one repo.

## Format

Each entry should have:
- A clear title
- What the wrong approach looks like
- What the right approach is
- Why (the underlying constraint or framework behavior)
