# Helpers shared by the forge lanes, imported by Forge.rb.
#
# Relies on FORGE_PROJECT_ROOT, defined by Forge.rb before this file is imported.

# Runs a shell command from the Flutter project root.
def forge_sh(command)
  Dir.chdir(FORGE_PROJECT_ROOT) { sh(command) }
end

# Flutter build arguments for an optional flavor.
# The entry point defaults to lib/main_<flavor>.dart when it exists, lib/main.dart otherwise.
def forge_flavor_args(flavor, target)
  return "" if flavor.to_s.empty? && target.to_s.empty?

  args = ""
  args += " --flavor #{flavor.to_s.shellescape}" unless flavor.to_s.empty?
  target = "lib/main_#{flavor}.dart" if target.to_s.empty? && File.exist?(File.join(FORGE_PROJECT_ROOT, "lib", "main_#{flavor}.dart"))
  args += " -t #{target.to_s.shellescape}" unless target.to_s.empty?
  args
end

# Whether the SonarQube analysis can be published: false (with a warning) when
# SONAR_TOKEN is missing locally, error in CI where a missing token is a misconfiguration.
def forge_sonar_token?
  return true unless ENV["SONAR_TOKEN"].to_s.empty?

  UI.user_error!("SONAR_TOKEN is not set: cannot send the metrics to SonarQube") if is_ci
  UI.important("SONAR_TOKEN is not set: the metrics will not be sent to SonarQube")
  false
end
