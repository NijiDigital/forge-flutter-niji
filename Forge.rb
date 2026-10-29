# Shared lanes of the Flutter forge.
#
# The forge is a submodule located in <project>/fastlane/forge and is imported
# from the project's fastlane/Fastfile with:
#
#     import("forge/Forge.rb")
#
# Project-specific values come from the project's fastlane folder:
#   - Appfile: app_identifier (iOS) and package_name (Android)
#   - Matchfile: iOS signing (repo, type, team...)
#   - .env.default / .env.<name>: settings listed below, loaded with --env <name>
#
# You can find the documentation at https://docs.fastlane.tools

# Absolute paths resolved at load time: __dir__ is relative to the fastlane folder
# and forge_sh runs commands from the project root.
FORGE_DIR = File.expand_path(__dir__) unless defined?(FORGE_DIR)
FORGE_PROJECT_ROOT = File.expand_path("../..", __dir__) unless defined?(FORGE_PROJECT_ROOT)

# Helpers (forge_sh, forge_setting...). import() resolves relative paths from
# the project's Fastfile, hence the absolute path.
import(File.join(FORGE_DIR, "Utils.rb"))

# Sets APP_BUILD_NAME and APP_BUILD_NUMBER (unless already set) from the tag, the
# release/x.y.z branch or pubspec.yaml, on Codemagic, GitLab CI and locally.
#
# Optional settings (environment):
#   FORGE_VERSION_TAG_REGEX    regex whose first group is the version in the tag
#                              (default: ^v?(\d+\.\d+\.\d+))
#   FORGE_BUILD_NUMBER_PREFIX  prefix of the build number (e.g. 100)
desc "Resolve the version name and build number"
lane :version_metadata do
  forge_resolve_version_metadata
end

# Prepares the project before analyzing, testing or building it (scripts/prepare.sh).
# Called by the build lanes; analyze.sh and test.sh run prepare.sh themselves.
#
# Optional settings (environment):
#   FORGE_CI_FILES           files written from environment variables, space-separated
#                            VAR:path entries (VAR?:path: optional variable)
#   FORGE_ANDROID_CI_FILES   same, only for the android platform lanes
#   FORGE_IOS_CI_FILES       same, only for the ios platform lanes
#   FORGE_PREPARE_SCRIPT     project script run (with bash) after the files are written
#   FORGE_BUILD_RUNNER       true runs build_runner after pub get (default: false)
desc "Prepare the project (version, CI files, dependencies, code generation)"
lane :prepare do
  forge_resolve_version_metadata

  platform = lane_context[SharedValues::PLATFORM_NAME]
  forge_script("prepare.sh", env: platform ? { "FORGE_PLATFORM" => platform } : {})
end

# Runs scripts/test.sh, also usable without Ruby (GitLab CI).
#
# Options:
#   coverage:true      generates coverage/lcov.info and the HTML reports (scripts/coverage_report.sh)
#   send_metrics:true  then publishes the SonarQube analysis (send_metrics lane), coverage included.
#                      SONAR_TOKEN is checked before the tests run: when it is missing, the
#                      analysis is skipped locally and the lane fails in CI.
#
# Optional settings (fastlane/.env.default or environment):
#   FORGE_COVERAGE_EXCLUDES  space-separated lcov patterns excluded from the filtered report
desc "Run Flutter tests"
lane :test do |options|
  args = []
  args << "--coverage" if options[:coverage]
  args << "--sonar" if options[:send_metrics]
  forge_script("test.sh", *args)
end

# Runs scripts/analyze.sh, also usable without Ruby (GitLab CI).
#
# Optional settings (fastlane/.env.default or environment):
#   FORGE_ANALYZE_ARGS  extra flutter analyze arguments (e.g. --no-fatal-infos)
desc "Run the Flutter static analysis"
lane :analyze do
  forge_script("analyze.sh")
end

# Publishes the SonarQube analysis of the current sources and of the existing
# coverage/lcov.info (scripts/send_metrics.sh). Usually run through
# `test send_metrics:true`, which runs the tests with coverage first.
#
# Static settings (project key, sources, exclusions, lcov path) are read by
# sonar-scanner from the project's sonar-project.properties. sonar.projectVersion is
# passed from APP_BUILD_NAME (see version_metadata).
#
# Settings (environment):
#   SONAR_TOKEN         SonarQube token (required)
#   SONAR_HOST_URL      SonarQube URL
#   SONAR_SCANNER_ARGS  extra sonar-scanner arguments (CI: branch / merge request analysis).
#                       When unset outside CI, the current Git branch is analysed.
desc "Send the metrics (analysis and coverage) to SonarQube"
lane :send_metrics do
  forge_script("send_metrics.sh")
end

# Options shared by build_android_release and build_ipa_release. Each one falls back to
# FORGE_<PLATFORM>_<SETTING> (e.g. FORGE_ANDROID_FLAVOR, FORGE_IOS_BUILD_NUMBER), then to
# the environment variable in brackets:
#   flavor:<name>                 --flavor (FLAVOR)
#   target:<path>                 entry point (FORGE_TARGET, default: lib/main.dart,
#                                 or lib/main_<flavor>.dart when it exists)
#   dart_defines:<list>           space-separated KEY=VALUE, each passed with --dart-define
#                                 (FORGE_DART_DEFINES, e.g. "ENV=dev API=https://...")
#   dart_define_from_file:<path>  --dart-define-from-file (FORGE_DART_DEFINE_FROM_FILE)
#   build_name:<x.y.z>            --build-name (APP_BUILD_NAME, see version_metadata)
#   build_number:<n>              --build-number (APP_BUILD_NUMBER, see version_metadata)
#   tree_shake_icons:false        adds --no-tree-shake-icons (FORGE_TREE_SHAKE_ICONS, default: true)
#   extra_args:<args>             extra flutter build arguments (FORGE_<PLATFORM>_BUILD_ARGS only)

platform :android do
  # Options: see above, plus
  #   type:apk|appbundle  artifact to build (FORGE_ANDROID_BUILD_TYPE, default: apk)
  #
  # Release signing is configured by the project's Gradle files (see README).
  desc "Build Android release (APK or App Bundle)"
  lane :build_android_release do |options|
    type = forge_setting(options, :type, "FORGE_ANDROID_BUILD_TYPE", "apk")
    UI.user_error!("Unknown Android build type '#{type}', expected apk or appbundle") unless %w[apk appbundle].include?(type)

    UI.message("Cleaning Flutter project...")
    forge_sh("fvm flutter clean")

    prepare

    command = ["fvm", "flutter", "build", type, "--release"] + forge_flutter_build_args(options, :android)
    UI.message("Building Flutter Android #{type} release...")
    forge_sh(*command)

    output = type == "apk" ? "build/app/outputs/flutter-apk/" : "build/app/outputs/bundle/"
    UI.success("Android #{type} built successfully in: #{output} 🎉")
  end

  desc "Build APK for release (alias of build_android_release type:apk)"
  lane :build_apk_release do |options|
    build_android_release(options.merge(type: "apk"))
  end
end

platform :ios do
  # Required settings (environment, e.g. CI variables):
  #   MATCH_KEYCHAIN_NAME      name of the keychain to create (also read by match)
  #   MATCH_KEYCHAIN_PASSWORD  password of the keychain (also read by match)
  desc "Setup signing for iOS"
  lane :signing_setup do
    if is_ci
      keychain_name = ENV.fetch("MATCH_KEYCHAIN_NAME")
      keychain_password = ENV.fetch("MATCH_KEYCHAIN_PASSWORD")

      UI.message("Creating keychain #{keychain_name}...")
      create_keychain(
        name: keychain_name,
        password: keychain_password,
        default_keychain: true,
        unlock: true,
        timeout: 0,
        lock_when_sleeps: false
      )

      UI.success("Keychain #{keychain_name} created and unlocked 🎉")

      match(
        keychain_name: keychain_name,
        keychain_password: keychain_password
      )
    else
      match
    end
  end

  # Options: see above, plus
  #   export_options_plist:<path>   --export-options-plist, relative to the project root
  #                                 (IOS_EXPORT_OPTIONS_PLIST_PATH). When unset,
  #                                 --export-method FORGE_IOS_EXPORT_METHOD is used instead.
  desc "Build IPA Release"
  lane :build_ipa_release do |options|
    export_options_plist = forge_setting(options, :export_options_plist, "IOS_EXPORT_OPTIONS_PLIST_PATH")
    if export_options_plist
      export_options_plist = File.expand_path(export_options_plist, FORGE_PROJECT_ROOT)
      UI.user_error!("Export options plist not found: #{export_options_plist}") unless File.exist?(export_options_plist)
    end

    UI.message("Starting Flutter clean...")
    forge_sh("fvm flutter clean")

    prepare

    UI.message("Setting up signing...")
    signing_setup

    UI.message("Installing CocoaPods dependencies...")
    cocoapods(podfile: File.join(FORGE_PROJECT_ROOT, "ios", "Podfile"))

    command = %w[fvm flutter build ipa --release] + forge_flutter_build_args(options, :ios)
    if export_options_plist
      command += ["--export-options-plist", export_options_plist]
    else
      command += ["--export-method", ENV.fetch("FORGE_IOS_EXPORT_METHOD", "enterprise")]
    end

    UI.message("Building Flutter iOS release...")
    forge_sh(*command)

    UI.success("iOS IPA built successfully and located at: build/ios/ipa/ 🎉")
  end
end
