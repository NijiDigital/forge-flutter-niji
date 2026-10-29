# Forge Flutter

This repository contains the Niji mobile team's **Flutter forge**: the [fastlane](https://docs.fastlane.tools) lanes shared across Flutter projects (Android and iOS builds).

Instead of copying these lanes into every project, the forge is added as a **Git submodule** in the project's `fastlane/` folder. Each project thus references a specific version of the forge and can update it whenever it wants. Project-specific configuration (identifiers, signing, gem versions) stays in the project.

## Adding the forge to an existing project

### 1. Initialize fastlane at the project root

The project must have a `Gemfile` at its root, with its `Gemfile.lock` committed:

```ruby
source "https://rubygems.org"

gem "fastlane"
```

```bash
bundle install
bundle exec fastlane init
```

This creates a `fastlane/` folder at the project root, with an `Appfile` and a `Fastfile`.

### 2. Add the forge as a submodule

Still from the project root:

```bash
git submodule add https://github.com/NijiDigital/forge-flutter-niji.git fastlane/forge
```

This command clones the forge into `fastlane/forge/`, creates (or updates) the `.gitmodules` file and stages both.

### 3. Import the forge lanes

In `fastlane/Fastfile`:

```ruby
import("forge/Forge.rb")

# Project-specific lanes can be added here.
```

### 4. Configure the project

Project-specific values live in its `fastlane/` folder:

```
<project>/
├── Gemfile / Gemfile.lock
└── fastlane/
    ├── Fastfile        # import("forge/Forge.rb") + project lanes
    ├── Appfile         # application identifiers
    ├── Matchfile       # iOS signing
    ├── .env.default    # optional settings for the forge lanes
    └── forge/          # this repository (submodule)
```

**`fastlane/Appfile`**

```ruby
app_identifier("com.example.app") # iOS bundle identifier
package_name("com.example.app")   # Android package name
```

**`fastlane/Matchfile`** (example with Niji Enterprise signing)

```ruby
git_url("<URL_FASTLANE_MATCH>")
storage_mode("git")
type("enterprise")
app_identifier(["com.example.app"])
readonly(true)
team_id("<TEAM_ID>")
```

**`fastlane/.env.default`** (optional, loaded automatically by fastlane) and **`fastlane/.env.<name>`** (loaded with `--env <name>`, e.g. one file per environment)

Build settings, shared by `build_android_release` and `build_ipa_release`. Each one can be set per platform with `FORGE_ANDROID_<SETTING>` / `FORGE_IOS_<SETTING>` (e.g. `FORGE_IOS_FLAVOR`, `FORGE_ANDROID_BUILD_NUMBER`), which takes precedence over the shared variable:

| Variable | Default | Purpose |
| --- | --- | --- |
| `FLAVOR` | _(none)_ | `--flavor` (option `flavor:`) |
| `FORGE_TARGET` | `lib/main.dart` or `lib/main_<flavor>.dart` | Entry point (option `target:`) |
| `FORGE_DART_DEFINES` | _(empty)_ | Space-separated `KEY=VALUE`, each passed with `--dart-define` (option `dart_defines:`) |
| `FORGE_DART_DEFINE_FROM_FILE` | _(none)_ | `--dart-define-from-file` (option `dart_define_from_file:`) |
| `APP_BUILD_NAME` / `APP_BUILD_NUMBER` | see [Version](#version) | `--build-name` / `--build-number` (options `build_name:` / `build_number:`) |
| `FORGE_TREE_SHAKE_ICONS` | `true` | `false` adds `--no-tree-shake-icons` (option `tree_shake_icons:`) |
| `FORGE_ANDROID_BUILD_ARGS` / `FORGE_IOS_BUILD_ARGS` | _(empty)_ | Extra `flutter build` arguments (option `extra_args:`) |
| `FORGE_ANDROID_BUILD_TYPE` | `apk` | `apk` or `appbundle` (option `type:`) |
| `IOS_EXPORT_OPTIONS_PLIST_PATH` | _(none)_ | `--export-options-plist`, relative to the project root (option `export_options_plist:`) |
| `FORGE_IOS_EXPORT_METHOD` | `enterprise` | `--export-method`, used when no export options plist is set |

Preparation settings (`prepare` lane, see [Preparation](#preparation)) and others:

| Variable | Default | Purpose |
| --- | --- | --- |
| `FORGE_CI_FILES` | _(empty)_ | Files written from environment variables: space-separated `VAR:path` (`VAR?:path` when the variable is optional) |
| `FORGE_ANDROID_CI_FILES` / `FORGE_IOS_CI_FILES` | _(empty)_ | Same, only for the `android` / `ios` lanes |
| `FORGE_PREPARE_SCRIPT` | _(none)_ | Project script run with `bash` after the files are written (e.g. to generate a `.env`) |
| `FORGE_BUILD_RUNNER` | `false` | `true` runs `dart run build_runner build --delete-conflicting-outputs` after `pub get` |
| `FORGE_VERSION_TAG_REGEX` | `^v?(\d+\.\d+\.\d+)` | Regex whose first group is the version name in the Git tag |
| `FORGE_BUILD_NUMBER_PREFIX` | _(empty)_ | Prefix of the generated build number |
| `FORGE_COVERAGE_EXCLUDES` | _(empty)_ | Space-separated lcov patterns excluded from the filtered coverage report (e.g. `lib/main.dart lib/pages/*`) |
| `FORGE_ANALYZE_ARGS` | _(empty)_ | Extra `flutter analyze` arguments of the `analyze` lane (e.g. `--no-fatal-infos` to fail only on warnings and errors) |

> Variables of a `.env.<name>` file loaded with `--env` override the variables already set in the environment: keep CI secrets out of these files.

On CI, the `signing_setup` lane (called by `build_ipa_release`) also requires two variables, with no default value, which are also read by match:

| Variable | Purpose |
| --- | --- |
| `MATCH_KEYCHAIN_NAME` | Name of the keychain to create (e.g. `ci.keychain`) |
| `MATCH_KEYCHAIN_PASSWORD` | Keychain password (CI secret variable) |

A variable already set in the environment (for example a CI variable) takes precedence over `fastlane/.env.default`, but not over a `.env.<name>` file loaded with `--env`.

Finally, ignore the reports generated by fastlane in the project's `.gitignore`:

```gitignore
fastlane/report.xml
fastlane/report.junit
```

### 5. Commit

```bash
git add .gitmodules Gemfile Gemfile.lock fastlane
git commit -m "chore: add fastlane with forge submodule"
```

## Available lanes

From the project root (add `--env <name>` to load `fastlane/.env.<name>`):

```bash
bundle exec fastlane test
bundle exec fastlane test coverage:true
bundle exec fastlane test send_metrics:true
bundle exec fastlane analyze
bundle exec fastlane send_metrics
bundle exec fastlane prepare
bundle exec fastlane version_metadata
```

```bash
bundle exec fastlane android build_android_release
bundle exec fastlane android build_android_release type:appbundle --env prod
bundle exec fastlane android build_apk_release flavor:dev
```

```bash
bundle exec fastlane ios build_ipa_release
bundle exec fastlane ios build_ipa_release flavor:prod
```

| Platform | Lane | Result |
| --- | --- | --- |
| All | `test` | `prepare`, then `flutter test` (with `coverage:true`: `coverage/lcov.info` + HTML reports, see below; with `send_metrics:true`: coverage then `send_metrics`) |
| All | `analyze` | `prepare`, then `flutter analyze` |
| All | `send_metrics` | Sends the analysis and the existing coverage (`coverage/lcov.info`) to SonarQube, see below |
| All | `prepare` | Version, CI files, project script, `pub get`, `build_runner`. Called by the other lanes, see below |
| All | `version_metadata` | Sets `APP_BUILD_NAME` / `APP_BUILD_NUMBER`, see below |
| Android | `build_android_release` | `build/app/outputs/flutter-apk/*.apk` or, with `type:appbundle`, `build/app/outputs/bundle/**/*.aab` |
| Android | `build_apk_release` | Alias of `build_android_release type:apk` |
| iOS | `signing_setup` | Fetches certificates via match; on CI, first creates a temporary keychain. Called by `build_ipa_release` |
| iOS | `build_ipa_release` | `build/ios/ipa/*.ipa` via `flutter build ipa` (certificates fetched via match) |

Flutter commands are run through `fvm` from the project root.

### Flavors

`build_android_release` and `build_ipa_release` accept `flavor:<name>` and `target:<path>`:

- `--flavor <name>` is passed to `flutter build`;
- the entry point is `target:` if provided, otherwise `lib/main_<name>.dart` if it exists, otherwise `lib/main.dart`.

When only one platform uses flavors, set `FORGE_IOS_FLAVOR` (or `FORGE_ANDROID_FLAVOR`) instead of `FLAVOR`.

### Version

`version_metadata` (called by `prepare`) sets the variables below, unless they are already set. It works the same on Codemagic, GitLab CI and locally:

| Variable | Value |
| --- | --- |
| `APP_BUILD_NAME` | Version captured by `FORGE_VERSION_TAG_REGEX` in the tag (`CM_TAG` / `CI_COMMIT_TAG`, e.g. `v1.2.3-beta` → `1.2.3`), otherwise `x.y.z` of a `release/x.y.z` branch (`CM_BRANCH` / `CI_COMMIT_BRANCH`), otherwise the `pubspec.yaml` version |
| `APP_BUILD_NUMBER` | `FORGE_BUILD_NUMBER_PREFIX` + the first of `PROJECT_BUILD_NUMBER`, `BUILD_NUMBER` (Codemagic), `CI_PIPELINE_IID` (GitLab), `1` |

### Preparation

`prepare` runs, in this order:

1. `version_metadata`;
2. writes the files of `FORGE_CI_FILES` (and `FORGE_ANDROID_CI_FILES` / `FORGE_IOS_CI_FILES` in the platform lanes) from CI secret variables, e.g. `FIREBASE_PLIST:ios/Runner/GoogleService-Info.plist LOCAL_PROPERTIES?:android/local.properties`. A missing required variable fails on CI and only warns locally, so that local files are kept;
3. `FORGE_PREPARE_SCRIPT`, for project-specific steps (it can read `APP_BUILD_NAME` / `APP_BUILD_NUMBER`);
4. `flutter pub get`, then `build_runner` when `FORGE_BUILD_RUNNER=true`.

### Android signing

The forge does not sign the Android build itself: the project's `android/app/build.gradle` reads the release keystore. Convention used by the CI templates (GitLab: `ANDROID_KEYSTORE_PATH` as a *File* variable, the others masked):

```groovy
signingConfigs {
  release {
    if (System.getenv("ANDROID_KEYSTORE_PATH")) {
      storeFile file(System.getenv("ANDROID_KEYSTORE_PATH"))
      storePassword System.getenv("ANDROID_KEYSTORE_PASSWORD")
      keyAlias System.getenv("ANDROID_KEY_ALIAS")
      keyPassword System.getenv("ANDROID_KEY_PASSWORD")
    }
  }
}
```

### SonarQube analysis

`bundle exec fastlane test send_metrics:true` runs the tests with coverage, then the `send_metrics` lane. `SONAR_TOKEN` is checked **before** the tests: if it is missing, the upload is skipped locally (a warning is shown, tests still run) and the lane fails on CI.

The `send_metrics` lane can also be run on its own, on previously generated coverage. It reads the static configuration from the project's `sonar-project.properties`: key, sources, exclusions, `sonar.dart.lcov.reportPaths=coverage/lcov.info`. `sonar.projectVersion` is passed from the resolved app version (`APP_BUILD_NAME`, see `version_metadata`): do not set it in `sonar-project.properties`. `sonar-scanner` must be installed (`brew install sonar-scanner` locally). Never commit the token in `sonar-project.properties`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SONAR_TOKEN` | _(required)_ | SonarQube token |
| `SONAR_HOST_URL` | _(none)_ | Server URL (or `sonar.host.url` in `sonar-project.properties`) |
| `SONAR_SCANNER_ARGS` | _(empty)_ | Extra `sonar-scanner` arguments (on CI: branch or MR analysis). When empty outside CI, the current Git branch is analyzed |

### Coverage report

With `coverage:true`, the `test` lane then runs `scripts/coverage_report.sh` (installs `lcov` if missing, via Homebrew on macOS or apt-get on Linux), which generates in `coverage/`:

| File | Content |
| --- | --- |
| `html/` | Full HTML report |
| `lcov_filtered.info`, `html_filtered/` | Filtered report (if `FORGE_COVERAGE_EXCLUDES` is set) |
| `coverage_html.zip` | Zipped HTML reports (CI artifact) |

Coverage summaries are printed to the console.

## CI: GitLab CI (Linux) + Codemagic (iOS)

Recommended setup: analysis, tests, SonarQube and Android builds run on GitLab CI (Linux runner); iOS builds run on Codemagic (macOS), triggered and followed by a GitLab job. Every CI step is a fastlane lane or a forge script, so it can also be run locally.

| File | Purpose |
| --- | --- |
| `ci/gitlab/forge.gitlab-ci.yml` | Hidden jobs to extend: `.forge_flutter_linux`, `.forge_analyze`, `.forge_test_sonar`, `.forge_android_build`, `.forge_codemagic` (former name `.forge_codemagic_ios`, still accepted) |
| `ci/codemagic/codemagic.template.yaml` | iOS workflow template to copy to the project's `codemagic.yaml` |
| `scripts/setup_fvm.sh` | Installs the Flutter version of `.fvmrc` with FVM (GitLab and Codemagic), reusing the SDK on the `PATH` when it is that version (e.g. `cirruslabs/flutter:<version>` image) |
| `scripts/codemagic_build.sh` | Triggers a Codemagic workflow, follows it and downloads its artifacts |

GitLab resolves includes before cloning the repository, so it cannot read a file from a submodule. Copy the template to the project and include the copy:

```bash
mkdir -p .gitlab
cp fastlane/forge/ci/gitlab/forge.gitlab-ci.yml .gitlab/
```

```yaml
include:
  - local: .gitlab/forge.gitlab-ci.yml

variables:
  FORGE_FLUTTER_IMAGE: ghcr.io/cirruslabs/flutter:<version of .fvmrc>

analyze:
  extends: .forge_analyze
  variables:
    FORGE_FASTLANE_ENV: dev

android_release:
  extends: .forge_android_build
  variables:
    FORGE_FASTLANE_ENV: prod
    FORGE_ANDROID_BUILD_TYPE: appbundle
  rules:
    - if: $CI_COMMIT_TAG

ios_release:
  extends: .forge_codemagic
  variables:
    CODEMAGIC_WORKFLOW_ID: ios_prod
  rules:
    - if: $CI_COMMIT_TAG
```

`.forge_flutter_linux` installs Ruby and the bundle if needed, runs `setup_fvm.sh` and caches the pub, FVM, Gradle and bundler folders. `.forge_test_sonar` downloads `sonar-scanner` when the image does not provide it (checked against `FORGE_SONAR_SCANNER_SHA256`) and computes `SONAR_SCANNER_ARGS` for merge requests and branches.

### Codemagic builds triggered from GitLab CI

`scripts/codemagic_build.sh <workflowId> [artifacts_dir]` triggers a Codemagic workflow through the API on the pipeline's branch (or tag), follows its execution and downloads its artifacts (default: `codemagic-artifacts/`). The job fails if the build does not end with the `finished` or `warning` status. `.forge_codemagic` also cancels the Codemagic build when the GitLab job is canceled.

Required CI/CD variables: `CODEMAGIC_API_TOKEN` (masked), `CODEMAGIC_APP_ID`. Optional: `CODEMAGIC_POLL_INTERVAL` (seconds, default 30).

Remove the `triggering` section of these Codemagic workflows, otherwise a tag starts the build twice.

## Managing the submodule

### Cloning a project that already uses the forge

```bash
git clone --recurse-submodules <project-url>
```

If the project was already cloned without its submodules:

```bash
git submodule update --init --recursive
```

### Updating the forge

```bash
git submodule update --remote fastlane/forge
cp fastlane/forge/ci/gitlab/forge.gitlab-ci.yml .gitlab/
git add fastlane/forge .gitlab/forge.gitlab-ci.yml
git commit -m "chore: update forge submodule"
```

Copy the GitLab CI template again at each update, so that the project's jobs match the new forge version.

The project then points to the new forge commit; other team members get this version with `git submodule update`.

### Removing the forge

```bash
git submodule deinit -f fastlane/forge
git rm -f fastlane/forge
# The folder is named after the submodule: fastlane/forge by default, forge on older projects
rm -rf .git/modules/fastlane/forge .git/modules/forge
git commit -m "chore: remove forge submodule"
```

Then remember to remove `import("forge/Forge.rb")` from `fastlane/Fastfile`.

## Contributing

Changes to the forge must be made in this repository (not directly from a project that uses it) through a pull request on [NijiDigital/forge-flutter-niji](https://github.com/NijiDigital/forge-flutter-niji).

If a lane needs a fastlane plugin, mention it here: each project will have to add it to its `Gemfile` / `Pluginfile`.
