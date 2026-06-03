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

## dorny/test-reporter: dart-json is the correct reporter for flutter test --machine
**Repo:** domiva-mobile
**PR:** #44
**Date:** 2026-06-01
**What went wrong:** The PR #13 fix agent changed `reporter: dart-test` to `reporter: flutter-machine`, believing v2+ renamed the reporter. But `flutter-machine` does not exist in any version of dorny/test-reporter -- that fix introduced a new CI failure. The original learning was recorded as if `flutter-machine` were correct, which would cause any agent reading it to re-introduce the broken value.
**Correct approach:** Use `reporter: dart-json` for the output of `flutter test --machine`. `flutter-machine` is not a valid reporter name in any version of dorny/test-reporter. The correct reporter for Flutter/Dart test machine output is `dart-json`.

## Use a tall test viewport when form fields fill or exceed 800x600
**Repo:** domiva-mobile
**PR:** #13
**Date:** 2026-05-17
**What went wrong:** A widget test used ensureVisible(find.text('Save changes')) to scroll a submit button into view inside a deep form. ListView builds children lazily -- the button was not in the render tree until it scrolled into the viewport, so ensureVisible threw "No element". Replacing with scrollUntilVisible also failed because TextFormField(maxLines: 3) creates an internal Scrollable inside EditableText, making find.byType(Scrollable) ambiguous ("Too many elements").
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
**What went wrong:** _loadContact() silently left the edit form blank when getByUuid returned null (missing contact) or threw a database exception. The catch block was misleadingly commented "Contact not found" even though getSingleOrNull() never throws for missing rows -- it only fires for real DB failures.
**Correct approach:** (1) When getByUuid returns null, show a snackbar (e.g. "Contact not found") and call context.pop() -- never leave the user on a blank edit form with no explanation. (2) In the catch block, show the error message (e.g. "Failed to load contact: $e") rather than swallowing it silently. Match the pattern used in _save(). (3) Add regression tests for both paths: FakeContactRepository with no matching UUID (null return), and with throwOnGetByUuid: true (DB error). When asserting snackbar text that also appears in a sibling screen body, use find.descendant(of: find.byType(SnackBar), matching: find.text(...)) to avoid ambiguity.

## Gitignored Flutter assets must be created in every build workflow
**Repo:** domiva-mobile
**PR:** #19
**Date:** 2026-05-20
**What went wrong:** distribute-android.yml was missing a step to create .env/dev.json before the build. The file is declared as a Flutter asset in pubspec.yaml but the .env/ directory is gitignored. ci.yml had the workaround but the distribution workflow did not, meaning flutter build appbundle --release would fail with a missing asset error on every push to main.
**Correct approach:** Any workflow that runs a Flutter build (flutter build, flutter test, etc.) must create all gitignored asset files before running flutter pub get. Check pubspec.yaml assets: for gitignored paths and add a creation step to every workflow that builds. For production builds, use a secret (e.g. RELEASE_ENV_CONFIG) with a fallback to production-appropriate defaults (USE_MOCK: false).

## iOS distribution: use Fastlane on macos-15, not xcrun altool on macos-14
**Repo:** domiva-mobile
**PR:** #66
**Date:** 2026-06-02
**What went wrong:** Earlier learnings (PR #35) instructed agents to pin the iOS distribution workflow to `runs-on: macos-14` because `xcrun altool` was removed in Xcode 16. Those entries also implied altool was the correct upload tool as long as macos-14 was pinned. Both are now wrong: macos-14 runners will eventually be retired, and altool is a dead end.
**Correct approach:** Use `runs-on: macos-15` (Xcode 16+) and Fastlane `upload_to_testflight` for iOS IPA uploads. `xcrun altool` was removed entirely in Xcode 16 — do NOT write any workflow that calls it. The Fastlane lane reads the App Store Connect API key from a JSON file written before the upload step. See PR #66 for the canonical workflow. Do NOT reintroduce `runs-on: macos-14` or `xcrun altool` — the previous learnings recommending them are superseded by this entry.

## find.byType(ListView) matches hidden parent-route ListViews in GoRouter tests
**Repo:** domiva-mobile
**PR:** #13
**Date:** 2026-05-27
**What went wrong:** A create-mode test used tester.drag(find.byType(ListView), ...) to scroll the submit button into view. With GoRouter nested routes (initialLocation: '/contacts/new'), both the parent ContactsScreen (filter-chips ListView) and AddEditContactScreen (form ListView) are fully built in the widget tree simultaneously -- MaterialPage.maintainState is true. find.byType(ListView) matched two elements and tester.drag threw StateError: Expected exactly one matching element.
**Correct approach:** Never use find.byType(ListView) for scrolling in a GoRouter test with nested routes -- the parent route's ListViews are also in the tree. Instead, use the tall-viewport pattern: set tester.view.physicalSize = const Size(800, 1200) and tester.view.devicePixelRatio = 1.0 at the top of the test (with addTearDown(tester.view.reset)). A tall viewport makes the submit button visible without any scrolling.

## ExportOptions.plist signingStyle does not override archive phase — set CODE_SIGN_STYLE=Manual in Release and Profile configs only
**Repo:** domiva-mobile
**PR:** #35
**Date:** 2026-05-28
**What went wrong:** ios/ExportOptions.plist with signingStyle=manual was added to fix headless CI signing, but CODE_SIGN_STYLE=Automatic remained in project.pbxproj. ExportOptions.plist only controls xcodebuild -exportArchive (the export phase); the xcodebuild archive phase (which runs first inside flutter build ipa) still used Automatic signing, causing xcodebuild to contact Apple's provisioning portal and fail on runners with no Apple ID session.
**Correct approach:** Set CODE_SIGN_STYLE=Manual on the Runner **Release** and **Profile** build configurations only in ios/Runner.xcodeproj/project.pbxproj. Also set `"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Distribution"` on those same two configs so the archive phase selects the distribution cert (not the development cert) when only an iPhone Distribution certificate is installed in CI.
**Do NOT set Manual on the Debug config.** Debug uses Automatic signing for local development -- `flutter run` on physical devices relies on Xcode managing the development profile automatically. Setting Manual on Debug without a PROVISIONING_PROFILE_SPECIFIER breaks local device builds. The distribute workflow only runs `--release`, so Debug signing is irrelevant to CI distribution.

## Android package rename requires directory migration that sandbox cannot delete
**Repo:** domiva-mobile
**PR:** #43
**Date:** 2026-05-30
**What went wrong:** When renaming applicationId/namespace in build.gradle, the Kotlin source directory (e.g. com/domiva/mobile_application/) must also be renamed to match. The fix agent sandbox blocks file deletion (rm, git rm), so the old directory cannot be removed programmatically. Creating only the new file leaves a stale placeholder and cleared old file in the tree.
**Correct approach:** Coding agents should handle Android package renames atomically using git mv (moves the file and tracks it in git). If a fix agent must handle it: (1) create the new MainActivity.kt at the correct path with the new package declaration, (2) overwrite the old file with only a comment (no class, no package declaration) to avoid a duplicate-class compile error, (3) add a prominent note in the PR comment that the old directory needs manual cleanup: git rm -r android/app/src/main/kotlin/com/

## xcrun altool ignores --apiKeyPath — key must be in a hardcoded directory
**Repo:** domiva-mobile
**PR:** #63
**Date:** 2026-06-02
**What went wrong:** The upload step wrote the .p8 key to $RUNNER_TEMP/authkey.p8 and passed --apiKeyPath to xcrun altool. altool silently ignores --apiKeyPath entirely; it resolves the API key by name (AuthKey_{KEY_ID}.p8) from a hardcoded set of directories only: ~/private_keys, ~/.private_keys, ~/.appstoreconnect/private_keys, or ./private_keys. Writing to any other path causes a "Failed to load AuthKey file" authentication error.
**Correct approach:** Write the .p8 to ~/.appstoreconnect/private_keys/AuthKey_{APPLE_API_KEY_ID}.p8 (create the directory with mkdir -p first). Do NOT pass --apiKeyPath -- it has no effect and will silently fail if the file is not also in one of the hardcoded locations.

## Multiline secrets must be escaped with jq when written to JSON files
**Repo:** domiva-mobile
**PR:** #66
**Date:** 2026-06-02
**What went wrong:** The "Write App Store Connect API key" step wrote the APPLE_API_KEY secret (a raw .p8 PEM file) directly into a JSON heredoc via `"key": "$APPLE_API_KEY"`. Raw .p8 files contain literal newline characters; embedding them inside a JSON string value violates RFC 8259 §7. Fastlane calls JSON.parse on this file and raises JSON::ParserError on every run.
**Correct approach:** Use `jq -Rs` to construct the JSON — `-R` reads raw text (not JSON), `-s` slurps all lines into one string with newlines escaped as `\n`. Example: `printf '%s' "$APPLE_API_KEY" | jq -Rs --arg kid "$APPLE_API_KEY_ID" --arg iid "$APPLE_API_ISSUER_ID" '{key_id: $kid, issuer_id: $iid, key: ., in_house: false}' > "$API_KEY_PATH"`. Never interpolate a multiline secret directly into a JSON string — always route it through jq.
