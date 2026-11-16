# Helpers shared by the forge lanes, imported by Forge.rb.
#
# Relies on FORGE_PROJECT_ROOT, defined by Forge.rb before this file is imported.

# Runs a shell command from the Flutter project root. Several arguments are
# escaped and joined by fastlane's sh.
def forge_sh(*command, **options)
  Dir.chdir(FORGE_PROJECT_ROOT) { sh(*command, **options) }
end

# Runs a forge script (scripts/<name>) with bash, with extra environment variables.
def forge_script(name, *args, env: {})
  command = env.map { |key, value| "#{key}=#{value.to_s.shellescape}" }
  command += ["bash", File.join(FORGE_DIR, "scripts", name)].map(&:shellescape)
  forge_sh((command + args.map(&:shellescape)).join(" "))
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

# Sets APP_BUILD_NAME and APP_BUILD_NUMBER, unless they are already set, from
# scripts/version.sh (see scripts/common.sh): same values on Codemagic, GitLab CI
# and locally, with or without Ruby.
def forge_resolve_version_metadata
  output = forge_sh("bash", File.join(FORGE_DIR, "scripts", "version.sh"), log: false)
  output.scan(/^(APP_BUILD_NAME|APP_BUILD_NUMBER)=(.*)$/) do |name, value|
    ENV[name] = value unless value.empty?
  end

  UI.message("Version: #{ENV['APP_BUILD_NAME']} (#{ENV['APP_BUILD_NUMBER']})")
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
