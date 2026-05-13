# Java Agent Learnings

Patterns observed and corrected by Fix Agents in Domiva Java/Spring Boot repos.
Read this before writing any Java code. Append to it after fixing a recurring issue.

These are things the Coding Agent got wrong that a Fix Agent had to correct.
The goal is that each mistake is made once, then never again.

## How to add an entry

After fixing an issue, if the mistake is likely to recur, append an entry using this format:

```
## [Brief pattern name]
**Repo:** domiva-cloud
**PR:** #N
**Date:** YYYY-MM-DD
**What went wrong:** One sentence describing the mistake.
**Correct approach:** What to do instead — specific enough that the next agent won't repeat it.
```

Use this file for: Spring Boot, JPA/Hibernate, Flyway migrations, Gradle, Java-specific patterns.
Use `cross-repo.md` for patterns that apply across all languages and stacks.

New stack, new file: if you are working in a stack that does not yet have a learnings file
(e.g. `node.md`, `typescript.md`), create one following this same format.

To write a new entry, use the same API pattern shown in `cross-repo.md` but targeting
`agent-learnings/java.md`.

---
