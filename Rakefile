#!/usr/bin/env ruby
# encoding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'gtin2atc/version'
require "bundler/gem_tasks"
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

# dependencies are now declared in gtin2atc.gemspec

desc 'Offer a gem task like hoe'
task :gem => :build do
  Rake::Task[:build].invoke
end

task :spec => :clean

desc 'Run gtin2atc with all commonly used combinations'
task :test => [:clean, :spec, :gem] do
  log_file = 'test_options.log'
  puts "Running test_options.rb with Output redirected to #{log_file}. This will take some time (e.g. 20 minutes)"
  # must use bash -o pipefail to catch error in test_options.rb and not tee
  # see http://stackoverflow.com/questions/985876/tee-and-exit-status
  res = system("bash -c 'set -o pipefail && ./test_options.rb 2>&1 | tee #{log_file}'")
  puts "Running test_options.rb returned #{res.inspect}. Output was redirected to #{log_file}"
  exit 1 unless res
end

require 'rake/clean'
CLEAN.include FileList['pkg/*.gem']
CLEAN.include FileList['*.zip*']
CLEAN.include FileList['*.xls*']
CLEAN.include FileList['*.xml*']
CLEAN.include FileList['*.dat*']
CLEAN.include FileList['*.tar.gz']
CLEAN.include FileList['*.txt.*']
CLEAN.include FileList['*.csv.*']
CLEAN.include FileList['*.zip.*']
CLEAN.include FileList['ruby*.tmp']
CLEAN.include FileList['data/download']
CLEAN.include FileList['duplicate_ean13_from_zur_rose.txt']
