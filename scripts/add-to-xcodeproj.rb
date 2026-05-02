#!/usr/bin/env ruby
# frozen_string_literal: true
# Add a Swift file to a target in Ikeru.xcodeproj.
# Usage: ruby scripts/add-to-xcodeproj.rb <relative/path/to/file.swift> <TargetName>
# Idempotent: if the file is already in the target it's a no-op.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../Ikeru.xcodeproj', __dir__)
file_rel = ARGV[0]
target_name = ARGV[1]
abort "usage: ruby add-to-xcodeproj.rb <relative/path.swift> <TargetName>" unless file_rel && target_name

abs_path = File.expand_path("../#{file_rel}", __dir__)
abort "file not found: #{abs_path}" unless File.exist?(abs_path)

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == target_name }
abort "target not found: #{target_name}. Available: #{project.targets.map(&:name)}" unless target

# Already registered?
already = target.source_build_phase.files_references.any? do |ref|
  ref.real_path.to_s == abs_path
end
if already
  puts "[skip] #{file_rel} already in #{target_name}"
  exit 0
end

# Find or create the group matching the directory hierarchy under the project root.
dir_parts = File.dirname(file_rel).split('/')
group = project.main_group
dir_parts.each do |part|
  child = group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && g.display_name == part }
  group = child || group.new_group(part, part)
end

ref = group.new_reference(abs_path)
target.add_file_references([ref])

project.save
puts "[ok]   added #{file_rel} -> #{target_name}"
