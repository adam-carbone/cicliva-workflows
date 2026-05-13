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
