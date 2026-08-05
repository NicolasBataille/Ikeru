#!/usr/bin/env ruby
# frozen_string_literal: true
# Wire up build-system pieces in Ikeru.xcodeproj (idempotent):
#   1. Register NotoSerifJP-*.ttf under the Fonts group + Ikeru Resources phase.
#   2. Embed the Watch app: Ikeru -> IkeruWatch dependency + "Embed Watch Content"
#      copy-files phase ($(CONTENTS_FOLDER_PATH)/Watch, products directory), mirroring
#      the existing "Embed Foundation Extensions" phase used for IkeruWidget.
#   3. If Ikeru/Views/Session/SessionConfigView.swift was deleted on disk, drop its
#      stale file reference and build files from the project.
# Usage: ruby scripts/fix-project-wiring.rb

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../Ikeru.xcodeproj', __dir__)
FONTS = %w[NotoSerifJP-Bold.ttf NotoSerifJP-Medium.ttf].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)

app = project.targets.find { |t| t.name == 'Ikeru' }
watch = project.targets.find { |t| t.name == 'IkeruWatch' }
abort 'Ikeru or IkeruWatch target not found' unless app && watch

# --- 1. Fonts -----------------------------------------------------------------
fonts_group = project.objects.find do |o|
  o.isa == 'PBXGroup' && o.path == 'Fonts'
end
abort 'Fonts group not found' unless fonts_group

FONTS.each do |name|
  abort "missing on disk: #{name}" unless File.exist?(File.expand_path("../Ikeru/Resources/Fonts/#{name}", __dir__))
  ref = fonts_group.files.find { |f| f.path == name }
  if ref
    puts "[skip] file reference exists: #{name}"
  else
    ref = fonts_group.new_reference(name)
    puts "[ok]   added file reference: #{name}"
  end
  app.resources_build_phase.add_file_reference(ref, true)
end

# --- 2. Watch embedding -------------------------------------------------------
# add_dependency is a no-op when the dependency already exists.
app.add_dependency(watch)
puts "[ok]   target dependency Ikeru -> IkeruWatch ensured"

embed = app.copy_files_build_phases.find { |p| p.name == 'Embed Watch Content' }
unless embed
  embed = app.new_copy_files_build_phase('Embed Watch Content')
  puts '[ok]   created copy-files phase "Embed Watch Content"'
end
embed.dst_subfolder_spec = Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:products_directory]
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
abort 'IkeruWatch has no product reference' unless watch.product_reference
build_file = embed.add_file_reference(watch.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] } if build_file.settings.nil?

# --- 3. Stale SessionConfigView.swift reference -------------------------------
scv_on_disk = File.exist?(File.expand_path('../Ikeru/Views/Session/SessionConfigView.swift', __dir__))
stale_refs = project.files.select { |f| f.path == 'SessionConfigView.swift' }
if !scv_on_disk && !stale_refs.empty?
  stale_refs.each do |ref|
    ref.build_files.each(&:remove_from_project)
    ref.remove_from_project
  end
  puts '[ok]   removed stale SessionConfigView.swift reference(s)'
elsif scv_on_disk
  puts '[skip] SessionConfigView.swift still on disk, left untouched'
else
  puts '[skip] no SessionConfigView.swift reference in project'
end

project.save
puts "[ok]   saved #{PROJECT_PATH}"

# --- Verification (fresh reopen) ----------------------------------------------
puts "\n--- VERIFY ---"
v = Xcodeproj::Project.open(PROJECT_PATH)
vapp = v.targets.find { |t| t.name == 'Ikeru' }

res_names = vapp.resources_build_phase.files.map(&:display_name)
FONTS.each do |name|
  puts "resources phase contains #{name}: #{res_names.include?(name)}"
end

vembed = vapp.copy_files_build_phases.find { |p| p.name == 'Embed Watch Content' }
if vembed
  puts "copy phase 'Embed Watch Content': dstSubfolderSpec=#{vembed.dst_subfolder_spec} dstPath=#{vembed.dst_path}"
  vembed.files.each { |bf| puts "  copies: #{bf.display_name} (settings=#{bf.settings.inspect})" }
else
  puts "copy phase 'Embed Watch Content': MISSING"
end

dep = vapp.dependencies.find { |d| d.target && d.target.name == 'IkeruWatch' }
puts "target dependency Ikeru -> IkeruWatch: #{dep ? 'present' : 'MISSING'}"

leftover = v.files.select { |f| f.path == 'SessionConfigView.swift' }
puts "SessionConfigView.swift references remaining: #{leftover.count}"

# Final sanity: reopen once more.
Xcodeproj::Project.open(PROJECT_PATH)
puts 'sanity reopen: OK'
