# Cross-Repo Agent Learnings

Patterns observed and corrected by Fix Agents across all Domiva repos.
Read this before writing any code. Append to it after fixing a recurring issue.

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

Use this file for: test discipline, git hygiene, general architecture patterns, security practices,
cross-cutting conventions that apply regardless of language or framework.

Use `java.md` for Java/Spring Boot/JPA/Flyway/Gradle patterns.
Use `flutter.md` for Flutter/Dart/FVM/pub patterns.

To write a new entry from within a workflow (bot token has org-wide write access):

```bash
RESPONSE=$(gh api repos/Domiva-Life/domiva-workflows/contents/agent-learnings/cross-repo.md \
  -H "Authorization: token $GH_TOKEN")
SHA=$(echo "$RESPONSE" | jq -r '.sha')
CURRENT=$(echo "$RESPONSE" | jq -r '.content' | base64 -d)
NEW_ENTRY="

## Your pattern name
**Repo:** $REPO
**PR:** #$PR_NUMBER
**Date:** $(date +%Y-%m-%d)
**What went wrong:** ...
**Correct approach:** ..."
UPDATED=$(printf '%s%s' "$CURRENT" "$NEW_ENTRY" | base64 | tr -d '\n')
gh api repos/Domiva-Life/domiva-workflows/contents/agent-learnings/cross-repo.md \
  --method PUT \
  --field message="Add agent learning from $REPO PR #$PR_NUMBER" \
  --field content="$UPDATED" \
  --field sha="$SHA"
```

---

## Pin third-party CI actions to commit SHAs
**Repo:** domiva-cloud
**PR:** #76
**Date:** 2026-05-15
**What went wrong:** dorny/test-reporter was referenced via mutable @v1 tag in a job with checks:write, pull-requests:write, and actions:write permissions — a supply-chain attack on the action repo could execute arbitrary code in CI with those elevated permissions.
**Correct approach:** Always pin third-party GitHub Actions to an immutable commit SHA (e.g. `uses: owner/action@<commit-sha>  # vX.Y.Z`). Use an inline comment to document the human-readable version. Prefer the latest stable release over older major versions that no longer receive security fixes.

## ./gradlew fails in CI when gradle-wrapper.jar is gitignored
**Repo:** domiva-cloud
**PR:** #77
**Date:** 2026-05-15
**What went wrong:** ci.yml was changed to use `./gradlew build` instead of `gradle build`. gradle-wrapper.jar is excluded by the *.jar rule in .gitignore and is never present in CI. Without it, ./gradlew fails immediately with ClassNotFoundException: org.gradle.wrapper.GradleWrapperMain. The inline comment in ci.yml explicitly warns against using ./gradlew, but the command was changed anyway. This is the second revert of this exact bug (first was c70a540, reintroduced in 5e307bc).
**Correct approach:** Always use `gradle build` (the system Gradle installed by gradle/actions/setup-gradle with gradle-version) in ci.yml. Never change this to `./gradlew build` — the wrapper JAR is gitignored. If you see `./gradlew` in ci.yml, treat it as a bug regardless of consistency arguments with other workflow files.
