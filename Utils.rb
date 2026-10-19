# Helpers shared by the forge lanes, imported by Forge.rb.
#
# Relies on FORGE_PROJECT_ROOT, defined by Forge.rb before this file is imported.

# Runs a shell command from the Flutter project root. Several arguments are
# escaped and joined by fastlane's sh.
def forge_sh(*command)
  Dir.chdir(FORGE_PROJECT_ROOT) { sh(*command) }
end

# Value of a lane option, falling back to environment variables (first non-empty
# one wins), then to a default. Empty values are treated as missing.
def forge_setting(options, key, env_names, default = nil)
  value = options[key]
  Array(env_names).each do |env_name|
    break unless value.to_s.empty?

    value = ENV[env_name]
  end
  value.to_s.empty? ? default : value
end

# Boolean setting: "false", "0" and "no" (any case) are false.
def forge_bool_setting(options, key, env_names, default)
  value = forge_setting(options, key, env_names)
  return default if value.nil?

  !%w[false 0 no].include?(value.to_s.downcase)
end

# First non-empty environment variable among env_names.
def forge_env(*env_names)
  env_names.map { |name| ENV[name] }.find { |value| !value.to_s.empty? }
end

# Whether the SonarQube analysis can be published: false (with a warning) when
# SONAR_TOKEN is missing locally, error in CI where a missing token is a misconfiguration.
def forge_sonar_token?
  return true unless ENV["SONAR_TOKEN"].to_s.empty?

  UI.user_error!("SONAR_TOKEN is not set: cannot send the metrics to SonarQube") if is_ci
  UI.important("SONAR_TOKEN is not set: the metrics will not be sent to SonarQube")
  false
end

# Missing setting: error in CI, where it is a misconfiguration, warning locally.
def forge_missing!(message)
  UI.user_error!(message) if is_ci
  UI.important(message)
end

# Sets APP_BUILD_NAME and APP_BUILD_NUMBER from the CI context, unless they are
# already set. Works on Codemagic (CM_*), GitLab CI (CI_*) and locally.
#
#   build name:   version captured by FORGE_VERSION_TAG_REGEX in the tag, then
#                 release/x.y.z branch, then pubspec.yaml
#   build number: FORGE_BUILD_NUMBER_PREFIX + (PROJECT_BUILD_NUMBER, BUILD_NUMBER,
#                 CI_PIPELINE_IID or 1)
def forge_resolve_version_metadata
  if ENV["APP_BUILD_NAME"].to_s.empty?
    tag = forge_env("CM_TAG", "CI_COMMIT_TAG")
    branch = forge_env("CM_BRANCH", "CI_COMMIT_BRANCH")
    tag_regex = Regexp.new(ENV.fetch("FORGE_VERSION_TAG_REGEX", '^v?(\d+\.\d+\.\d+)'))

    build_name = tag.to_s[tag_regex, 1]
    build_name ||= branch.to_s[%r{^release/(\d+\.\d+\.\d+)$}, 1]
    build_name ||= forge_pubspec_version_name
    ENV["APP_BUILD_NAME"] = build_name if build_name
  end

  if ENV["APP_BUILD_NUMBER"].to_s.empty?
    raw_build_number = forge_env("PROJECT_BUILD_NUMBER", "BUILD_NUMBER", "CI_PIPELINE_IID") || "1"
    ENV["APP_BUILD_NUMBER"] = "#{ENV['FORGE_BUILD_NUMBER_PREFIX']}#{raw_build_number}"
  end

  UI.message("Version: #{ENV['APP_BUILD_NAME']} (#{ENV['APP_BUILD_NUMBER']})")
end

# version: of pubspec.yaml, without the +build part.
def forge_pubspec_version_name
  pubspec = File.join(FORGE_PROJECT_ROOT, "pubspec.yaml")
  return nil unless File.exist?(pubspec)

  File.read(pubspec)[/^version:\s*([^+\s]+)/, 1]
end

# Writes files from environment variables (CI secrets), from a space-separated list
# of VAR:path entries (path relative to the project root). VAR?:path marks an
# optional variable. A missing variable leaves the existing file untouched.
def forge_write_ci_files(spec)
  spec.to_s.split.each do |entry|
    name, path = entry.split(":", 2)
    UI.user_error!("Invalid CI file entry '#{entry}', expected VAR:path") if name.to_s.empty? || path.to_s.empty?

    optional = name.end_with?("?")
    name = name.delete_suffix("?")
    content = ENV[name].to_s
    if content.empty?
      forge_missing!("#{name} is not set: #{path} not written") unless optional
      next
    end

    destination = File.join(FORGE_PROJECT_ROOT, path)
    FileUtils.mkdir_p(File.dirname(destination))
    File.write(destination, "#{content.chomp}\n")
    UI.message("Wrote #{path} from #{name}")
  end
end

# Arguments shared by `flutter build apk|appbundle|ipa`. Each option falls back to
# FORGE_<PLATFORM>_<SETTING>, then to the shared environment variable.
def forge_flutter_build_args(options, platform)
  prefix = "FORGE_#{platform.to_s.upcase}"
  flavor = forge_setting(options, :flavor, ["#{prefix}_FLAVOR", "FLAVOR"])
  target = forge_setting(options, :target, ["#{prefix}_TARGET", "FORGE_TARGET"])
  target ||= "lib/main_#{flavor}.dart" if flavor && File.exist?(File.join(FORGE_PROJECT_ROOT, "lib", "main_#{flavor}.dart"))
  dart_defines = forge_setting(options, :dart_defines, ["#{prefix}_DART_DEFINES", "FORGE_DART_DEFINES"]).to_s.shellsplit
  dart_define_from_file = forge_setting(options, :dart_define_from_file, ["#{prefix}_DART_DEFINE_FROM_FILE", "FORGE_DART_DEFINE_FROM_FILE"])
  build_name = forge_setting(options, :build_name, ["#{prefix}_BUILD_NAME", "APP_BUILD_NAME"])
  build_number = forge_setting(options, :build_number, ["#{prefix}_BUILD_NUMBER", "APP_BUILD_NUMBER"])
  tree_shake_icons = forge_bool_setting(options, :tree_shake_icons, ["#{prefix}_TREE_SHAKE_ICONS", "FORGE_TREE_SHAKE_ICONS"], true)
  extra_args = forge_setting(options, :extra_args, "#{prefix}_BUILD_ARGS").to_s.shellsplit

  args = []
  args += ["--flavor", flavor] if flavor
  args += ["-t", target] if target
  args += dart_defines.map { |define| "--dart-define=#{define}" }
  args << "--dart-define-from-file=#{dart_define_from_file}" if dart_define_from_file
  args << "--build-name=#{build_name}" if build_name
  args << "--build-number=#{build_number}" if build_number
  args << "--no-tree-shake-icons" unless tree_shake_icons
  args + extra_args
end
