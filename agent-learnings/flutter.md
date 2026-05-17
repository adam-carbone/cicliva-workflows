# Flutter Agent Learnings

Patterns observed and corrected by Fix Agents in Domiva Flutter/Dart repos.
Read this before writing any Flutter code. Append to it after fixing a recurring issue.

These are things the Coding Agent got wrong that a Fix Agent had to correct.
The goal is that each mistake is made once, then never again.

## How to add an entry

After fixing an issue, if the mistake is likely to recur, append an entry using this format:

```
## [Brief pattern name]
**Repo:** domiva-mobile
**PR:** #N
**Date:** YYYY-MM-DD
**What went wrong:** One sentence describing the mistake.
**Correct approach:** What to do instead -- specific enough that the next agent won't repeat it.
```

Use this file for: Flutter, Dart, FVM, pub dependencies, widget patterns, state management.
Use `cross-repo.md` for patterns that apply across all languages.

To write a new entry, use the same API pattern shown in `cross-repo.md` but targeting
`agent-learnings/flutter.md`.

---

## Biometric auth must update auth state and be testable via provider abstraction
**Repo:** domiva-mobile
**PR:** #14
**Date:** 2026-05-17
**What went wrong:** _handleFaceIdAuth() called platform biometrics but never updated AuthController state on success -- only called debugPrint. The biometric flow appeared to work but left isAuthenticated false, keeping the user on the login screen. The LocalAuthentication instance was also read directly from localAuthProvider, making the biometric call untestable (platform-channel crash in test runner).
**Correct approach:** (1) Add a dedicated loginWithBiometrics() method to AuthController that sets isAuthenticated: true -- do NOT reuse login(email, password) which requires credentials. (2) Wrap LocalAuthentication in a LocalAuthService abstract class provided via localAuthServiceProvider so tests can override it with a fake. (3) Test all three biometric paths: button hidden when unsupported, success updates isAuthenticated, failure leaves isAuthenticated unchanged.