#!/usr/bin/env ruby
# frozen_string_literal: true
# Idempotently wire the salvaged resources into the (redesign) Ikeru.xcodeproj:
#   1. NotoSerifJP-*.ttf  -> Fonts group + Ikeru "Copy Bundle Resources"
#      (the redesign's FontExtensions already calls Font.custom("NotoSerifJP-…")
#       but never shipped the font files, so glyphs silently fell back to system).
#   2. InfoPlist.xcstrings -> Localization group + Ikeru "Copy Bundle Resources"
#      (localizes the Info.plist permission usage strings, FR + EN).
# Watch embedding and the stale SessionConfigView reference are already handled
# on dev, so this script intentionally does NOT touch them.
# Usage: ruby scripts/wire-fonts-infoplist.rb

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../Ikeru.xcodeproj', __dir__)
FONTS = %w[NotoSerifJP-Bold.ttf NotoSerifJP-Medium.ttf].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == 'Ikeru' }
abort 'Ikeru target not found' unless app

# --- 1. Fonts -----------------------------------------------------------------
fonts_group = project.objects.find { |o| o.isa == 'PBXGroup' && o.path == 'Fonts' }
abort 'Fonts group not found' unless fonts_group

FONTS.each do |name|
  disk = File.expand_path("../Ikeru/Resources/Fonts/#{name}", __dir__)
  abort "missing on disk: #{name}" unless File.exist?(disk)
  ref = fonts_group.files.find { |f| f.path == name } || fonts_group.new_reference(name)
  already = app.resources_build_phase.files.any? { |bf| bf.file_ref == ref }
  app.resources_build_phase.add_file_reference(ref, true) unless already
  puts "[font] #{name} #{already ? '(already in resources)' : 'added to resources'}"
end

# --- 2. InfoPlist.xcstrings ----------------------------------------------------
loc_ref = project.files.find { |f| f.path == 'Localizable.xcstrings' }
abort 'Localizable.xcstrings reference not found (cannot locate Localization group)' unless loc_ref
loc_group = loc_ref.parent

info_disk = File.expand_path('../Ikeru/Localization/InfoPlist.xcstrings', __dir__)
abort 'InfoPlist.xcstrings missing on disk' unless File.exist?(info_disk)

info_ref = project.files.find { |f| f.path == 'InfoPlist.xcstrings' } ||
           loc_group.new_reference('InfoPlist.xcstrings')
info_ref.last_known_file_type = 'text.json.xcstrings'
already = app.resources_build_phase.files.any? { |bf| bf.file_ref == info_ref }
app.resources_build_phase.add_file_reference(info_ref, true) unless already
puts "[strings] InfoPlist.xcstrings #{already ? '(already in resources)' : 'added to resources'}"

project.save
puts 'saved.'
