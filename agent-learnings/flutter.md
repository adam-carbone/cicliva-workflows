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

## Android release signing must use conditional keystore check for local dev compatibility
**Repo:** domiva-mobile
**PR:** #19
**Date:** 2026-05-17
**What went wrong:** The release signingConfig set storeFile unconditionally, breaking `flutter run --release` locally because domiva-release.jks is never on developer machines (it is decoded from a CI secret at build time).
**Correct approach:** Always guard the storeFile assignment with `if (keystoreFile.exists())` in signingConfigs.release, and select the signingConfig in the release buildType with a ternary: `file('domiva-release.jks').exists() ? signingConfigs.release : signingConfigs.debug`. This preserves local debug-signed release builds while CI still produces a properly signed AAB.

## dorny/test-reporter v2+ renamed dart-test reporter to flutter-machine
**Repo:** domiva-mobile
**PR:** #13
**Date:** 2026-05-17
**What went wrong:** ci.yml used `reporter: dart-test` with dorny/test-reporter pinned to a v3.0.0 commit SHA. dart-test was the v1 reporter name; v2+ renamed it to flutter-machine. The action rejected the value at startup and the build step failed.
**Correct approach:** Use `reporter: flutter-machine` for the output of `flutter test --machine`. If upgrading dorny/test-reporter across major versions, verify the reporter name is still valid — the mapping of Flutter output formats to reporter names can change between major versions.

## Use a tall test viewport when form fields fill or exceed 800x600
**Repo:** domiva-mobile
**PR:** #13
**Date:** 2026-05-17
**What went wrong:** A widget test used ensureVisible(find.text('Save changes')) to scroll a submit button into view inside a deep form. ListView builds children lazily — the button was not in the render tree until it scrolled into the viewport, so ensureVisible threw "No element". Replacing with scrollUntilVisible also failed because TextFormField(maxLines: 3) creates an internal Scrollable inside EditableText, making find.byType(Scrollable) ambiguous ("Too many elements").
**Correct approach:** When a form with 5+ fields plus NavigationBar (80dp) and AppBar (56dp) must all fit in a 600dp viewport, set `tester.view.physicalSize = const Size(800, 1200)` and `tester.view.devicePixelRatio = 1.0` at the top of the test, with `addTearDown(tester.view.reset)`. This ensures all form items are in the render tree with no scrolling needed. Note: any TextFormField with maxLines > 1 always creates a second internal Scrollable even with empty text.

## Placeholder navigation tests must be replaced when routes are wired
**Repo:** domiva-mobile
**PR:** #13
**Date:** 2026-05-17
**What went wrong:** Two tests in contacts_screen_test.dart used a bare MaterialApp (no GoRouter), causing context.push() to throw and fall into a catch block that showed a snackbar. The tests asserted the snackbar appeared, which was a valid placeholder before routes existed but became dead-code coverage once routes were wired -- the actual navigation path was completely untested.
**Correct approach:** When routes are wired, update or replace any tests that assert fallback/snackbar behavior from the catch block. Use a GoRouter-wired test app (MaterialApp.router with route definitions mirroring production) and assert that tapping navigation triggers (FAB, list rows, etc.) renders the correct destination screen. Extract the shared router test app to test/helpers/ so it can be reused across test files without duplication.

## _loadContact must surface errors: pop on null, snackbar on exception
**Repo:** domiva-mobile
**PR:** #13
**Date:** 2026-05-17
**What went wrong:** _loadContact() silently left the edit form blank when getByUuid returned null (missing contact) or threw a database exception. The catch block was misleadingly commented "Contact not found" even though getSingleOrNull() never throws for missing rows — it only fires for real DB failures.
**Correct approach:** (1) When getByUuid returns null, show a snackbar (e.g. "Contact not found") and call context.pop() — never leave the user on a blank edit form with no explanation. (2) In the catch block, show the error message (e.g. "Failed to load contact: $e") rather than swallowing it silently. Match the pattern used in _save(). (3) Add regression tests for both paths: FakeContactRepository with no matching UUID (null return), and with throwOnGetByUuid: true (DB error). When asserting snackbar text that also appears in a sibling screen body, use find.descendant(of: find.byType(SnackBar), matching: find.text(...)) to avoid ambiguity.

## Gitignored Flutter assets must be created in every build workflow
**Repo:** domiva-mobile
**PR:** #19
**Date:** 2026-05-20
**What went wrong:** distribute-android.yml was missing a step to create .env/dev.json before the build. The file is declared as a Flutter asset in pubspec.yaml but the .env/ directory is gitignored. ci.yml had the workaround but the distribution workflow did not, meaning flutter build appbundle --release would fail with a missing asset error on every push to main.
**Correct approach:** Any workflow that runs a Flutter build (flutter build, flutter test, etc.) must create all gitignored asset files before running flutter pub get. Check pubspec.yaml assets: for gitignored paths and add a creation step to every workflow that builds. For production builds, use a secret (e.g. RELEASE_ENV_CONFIG) with a fallback to production-appropriate defaults (USE_MOCK: false).

## xcrun altool removed in Xcode 16 — pin distribute workflow to macos-14
**Repo:** domiva-mobile
**PR:** #35
**Date:** 2026-05-27
**What went wrong:** distribute-ios.yml used runs-on: macos-latest and invoked xcrun altool --upload-app. An inline comment incorrectly claimed altool was only deprecated for --notarize-app and that iOS uploads remained supported. In fact, Apple removed altool entirely in Xcode 16. macos-latest now maps to macOS 15 / Xcode 16, so the upload step fails with "command not found".
**Correct approach:** Pin the iOS distribution job to runs-on: macos-14 (Xcode 15) where altool still exists. Add a comment explaining the pin and documenting the migration path to Fastlane upload_to_testflight. Do NOT write comments claiming partial deprecation without verifying the exact scope of removal. See docs/adr/002-ios-distribution-altool-xcode16.md.

## xcrun altool removed in Xcode 16 — pin distribute-ios to macos-14
**Repo:** domiva-mobile
**PR:** #35
**Date:** 2026-05-27
**What went wrong:** distribute-ios.yml used `runs-on: macos-latest` (now macOS 15 / Xcode 16) and included an incorrect inline comment claiming altool was only deprecated for `--notarize-app`. In reality, Apple removed altool entirely in Xcode 16 — all subcommands including `--upload-app` for iOS IPA uploads are gone.
**Correct approach:** Pin iOS distribution workflows that use `xcrun altool --upload-app` to `runs-on: macos-14` (Xcode 15) where altool is still present. Add a comment explaining the pin and the migration path (Fastlane `upload_to_testflight`) for when macos-14 runners are retired. Never write comments claiming altool deprecation is scoped only to notarization — the entire tool was removed in Xcode 16.
