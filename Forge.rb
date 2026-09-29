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
#   - .env.default: optional settings listed below
#
# You can find the documentation at https://docs.fastlane.tools

# Absolute paths resolved at load time: __dir__ is relative to the fastlane folder
# and forge_sh runs commands from the project root.
FORGE_DIR = File.expand_path(__dir__) unless defined?(FORGE_DIR)
FORGE_PROJECT_ROOT = File.expand_path("../..", __dir__) unless defined?(FORGE_PROJECT_ROOT)

# Helpers (forge_sh, forge_flavor_args...). import() resolves relative paths from
# the project's Fastfile, hence the absolute path.
import(File.join(FORGE_DIR, "Utils.rb"))

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
  # Checked before the tests so that a missing token does not fail after a full test run
  publish_metrics = options[:send_metrics] && forge_sonar_token?
  coverage = options[:coverage] || publish_metrics

  UI.message("Fetching Flutter dependencies...")
  forge_sh("fvm flutter pub get")

  UI.message("Running Flutter tests...")
  command = "fvm flutter test"
  command += " --coverage" if coverage
  forge_sh(command)

  UI.success("Flutter tests passed 🎉")

  if coverage
    UI.message("Generating coverage reports...")
    forge_sh("bash #{File.join(FORGE_DIR, "scripts", "coverage_report.sh").shellescape}")
    UI.success("Coverage reports generated in: coverage/ 🎉")
  end

  send_metrics if publish_metrics
end

desc "Run the Flutter static analysis"
lane :analyze do
  UI.message("Fetching Flutter dependencies...")
  forge_sh("fvm flutter pub get")

  UI.message("Running Flutter analyze...")
  forge_sh("fvm flutter analyze")

  UI.success("Flutter analyze passed 🎉")
end

# Publishes the SonarQube analysis of the current sources and of the existing
# coverage/lcov.info. Usually run through `test send_metrics:true`, which runs
# the tests with coverage first.
#
# Static settings (project key, sources, exclusions, lcov path) are read by
# sonar-scanner from the project's sonar-project.properties.
#
# Settings (environment):
#   SONAR_TOKEN         SonarQube token (required)
#   SONAR_HOST_URL      SonarQube URL
#   SONAR_SCANNER_ARGS  extra sonar-scanner arguments (CI: branch / merge request analysis).
#                       When unset outside CI, the current Git branch is analysed.
desc "Send the metrics (analysis and coverage) to SonarQube"
lane :send_metrics do
  UI.user_error!("SONAR_TOKEN is not set") if ENV["SONAR_TOKEN"].to_s.empty?
  UI.user_error!("sonar-scanner not found: install it (e.g. brew install sonar-scanner)") unless system("command -v sonar-scanner > /dev/null")
  UI.important("coverage/lcov.info not found: the analysis will have no coverage") unless File.exist?(File.join(FORGE_PROJECT_ROOT, "coverage", "lcov.info"))

  args = ENV["SONAR_SCANNER_ARGS"].to_s
  args = "-Dsonar.branch.name=#{git_branch.shellescape}" if args.empty? && !is_ci

  UI.message("Running SonarQube analysis...")
  forge_sh("sonar-scanner #{args}".strip)
  UI.success("SonarQube analysis published 🎉")
end

platform :android do
  # Options:
  #   flavor:<name>  builds this flavor (entry point lib/main_<name>.dart when it exists)
  #   target:<path>  entry point (default: lib/main.dart, or lib/main_<flavor>.dart)
  desc "Build APK for release"
  lane :build_apk_release do |options|
    flavor = options[:flavor]

    UI.message("Cleaning Flutter project...")
    forge_sh("fvm flutter clean")

    UI.message("Building Flutter APK release#{" (#{flavor})" if flavor}...")
    forge_sh("fvm flutter build apk --release#{forge_flavor_args(flavor, options[:target])}")

    apk_name = flavor ? "app-#{flavor}-release.apk" : "app-release.apk"
    UI.success("APK built successfully at: build/app/outputs/flutter-apk/#{apk_name} 🎉")
  end
end

platform :ios do
  # Optional settings (fastlane/.env.default or environment):
  #   FORGE_IOS_IPA_NAME       IPA file name (default: Runner.ipa)
  #   FORGE_IOS_EXPORT_METHOD  build_app export method (default: enterprise)
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

  # Options:
  #   flavor:<name>  builds this flavor: Xcode scheme <name>, configuration Release-<name>,
  #                  entry point lib/main_<name>.dart when it exists
  #   target:<path>  entry point (default: lib/main.dart, or lib/main_<flavor>.dart)
  desc "Build IPA Release"
  lane :build_ipa_release do |options|
    flavor = options[:flavor]
    ipa_name = ENV.fetch("FORGE_IOS_IPA_NAME", "Runner.ipa")

    UI.message("Starting Flutter clean...")
    forge_sh("fvm flutter clean")

    UI.message("Setting up signing...")
    signing_setup

    UI.message("Building Flutter iOS release#{" (#{flavor})" if flavor}...")
    forge_sh("fvm flutter build ios --release#{forge_flavor_args(flavor, options[:target])}")

    UI.message("Building iOS IPA file...")
    build_app(
      workspace: File.join(FORGE_PROJECT_ROOT, "ios", "Runner.xcworkspace"),
      scheme: flavor || "Runner",
      configuration: flavor ? "Release-#{flavor}" : "Release",
      silent: true,
      clean: true,
      output_directory: File.join(FORGE_PROJECT_ROOT, "build", "fastlane", "ipa"),
      output_name: ipa_name,
      export_method: ENV.fetch("FORGE_IOS_EXPORT_METHOD", "enterprise")
    )

    UI.success("iOS IPA built successfully and located at: build/fastlane/ipa/#{ipa_name} 🎉")
  end
end
