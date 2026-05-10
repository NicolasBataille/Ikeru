#!/usr/bin/env ruby
# Add Swift files to the Ikeru Xcode target.
#
# Usage:
#   scripts/add-to-xcode.rb <project> <target> <group/path/in/xcode> <file1> [file2 ...]
#
# Example:
#   scripts/add-to-xcode.rb Ikeru.xcodeproj Ikeru \
#     Ikeru/Views/Shared/Theme/Tatami \
#     Ikeru/Views/Shared/Theme/Tatami/TatamiTokens.swift \
#     Ikeru/Views/Shared/Theme/Tatami/SerifNumeral.swift
#
# The script:
#   - Creates intermediate Xcode groups under the project as needed
#   - Adds file references with the right source-tree (group-relative)
#   - Adds each file to the target's Sources build phase (Swift files)
#     or the Resources build phase (.xcstrings, .json, etc.)
#   - Skips files already present in the project

require 'xcodeproj'

if ARGV.length < 4
  puts "Usage: #{$0} <project> <target> <group/path> <file> [file...]"
  exit 1
end

project_path = ARGV.shift
target_name = ARGV.shift
group_path = ARGV.shift
file_paths = ARGV

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == target_name }
unless target
  abort "Target #{target_name.inspect} not found. Available: #{project.targets.map(&:name)}"
end

# Walk to the target group, creating missing groups along the way
group = project.main_group
group_path.split('/').each do |segment|
  next if segment.empty?
  child = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == segment }
  if child.nil?
    child = group.new_group(segment, segment)
  end
  group = child
end

added = 0
skipped = 0
file_paths.each do |file_path|
  basename = File.basename(file_path)

  # Already in this group?
  existing = group.files.find { |f| f.path == basename || f.display_name == basename }
  if existing
    skipped += 1
    next
  end

  file_ref = group.new_file(File.expand_path(file_path))
  # Make path relative to the group folder for cleaner project file
  file_ref.path = basename
  file_ref.source_tree = '<group>'

  ext = File.extname(basename).downcase
  case ext
  when '.swift'
    target.add_file_references([file_ref])
  when '.xcstrings', '.strings', '.json', '.plist', '.png', '.jpg'
    target.resources_build_phase.add_file_reference(file_ref)
  else
    target.add_file_references([file_ref])
  end
  added += 1
end

project.save
puts "Added #{added}, skipped #{skipped} (already in project) → group '#{group_path}'"
