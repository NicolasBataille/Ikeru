#!/usr/bin/env ruby
# frozen_string_literal: true
# Wire InfoPlist.xcstrings into Ikeru.xcodeproj (idempotent):
#   Register Ikeru/Localization/InfoPlist.xcstrings under the Localization
#   group + the Ikeru target's Resources phase, mirroring how
#   Localizable.xcstrings is wired. An .xcstrings catalogue named "InfoPlist"
#   in the app target's resources localizes Info.plist usage-description keys.
# Usage: ruby scripts/add-infoplist-strings.rb

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../Ikeru.xcodeproj', __dir__)
FILE_NAME = 'InfoPlist.xcstrings'

project = Xcodeproj::Project.open(PROJECT_PATH)

app = project.targets.find { |t| t.name == 'Ikeru' }
abort 'Ikeru target not found' unless app

# --- Localization group --------------------------------------------------------
loc_group = project.objects.find do |o|
  o.isa == 'PBXGroup' && o.path == 'Localization'
end
abort 'Localization group not found' unless loc_group

abort "missing on disk: #{FILE_NAME}" unless File.exist?(File.expand_path("../Ikeru/Localization/#{FILE_NAME}", __dir__))

ref = loc_group.files.find { |f| f.path == FILE_NAME }
if ref
  puts "[skip] file reference exists: #{FILE_NAME}"
else
  ref = loc_group.new_reference(FILE_NAME)
  puts "[ok]   added file reference: #{FILE_NAME}"
end
ref.last_known_file_type = 'text.json.xcstrings'
ref.include_in_index = '1'

# add_file_reference with avoid_duplicates=true is a no-op when already present.
app.resources_build_phase.add_file_reference(ref, true)
puts "[ok]   #{FILE_NAME} ensured in Ikeru Resources phase"

project.save
puts "[ok]   saved #{PROJECT_PATH}"

# --- Verification (fresh reopen) ----------------------------------------------
puts "\n--- VERIFY ---"
v = Xcodeproj::Project.open(PROJECT_PATH)
vapp = v.targets.find { |t| t.name == 'Ikeru' }

res_names = vapp.resources_build_phase.files.map(&:display_name)
puts "Ikeru Resources phase files:"
res_names.each { |n| puts "  #{n}" }
puts "resources phase contains #{FILE_NAME}: #{res_names.include?(FILE_NAME)}"
puts "resources phase #{FILE_NAME} count: #{res_names.count(FILE_NAME)} (expect 1)"

vgroup = v.objects.find { |o| o.isa == 'PBXGroup' && o.path == 'Localization' }
puts "Localization group children: #{vgroup.files.map(&:path).inspect}"

# Final sanity: reopen once more.
Xcodeproj::Project.open(PROJECT_PATH)
puts 'sanity reopen: OK'
