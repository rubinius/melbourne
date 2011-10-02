require "rake/extensiontask"
require "rubygems/package_task"

desc "Compile the C extension"
Rake::ExtensionTask.new('melbourne')

gemspec = eval(File.read("melbourne.gemspec"))
desc "Build the gem"
Gem::PackageTask.new(gemspec).define

desc "Install the gem"
task :install => :repackage do
  sh "gem install pkg/melbourne-*.gem"
end
