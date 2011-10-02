# encoding: utf-8

$:.unshift File.expand_path('../lib', __FILE__)
require 'melbourne/version'

Gem::Specification.new do |s|
  s.name         = "melbourne"
  s.version      = Melbourne::VERSION
  s.authors      = ["Evan Phoenix", "Bryan Ford", "Bryan Helmkamp"]
  s.email        = "bryan@brynary.com"
  s.homepage     = "https://github.com/rubinius/melbourne"
  s.summary      = "Rubinius Melbourne parser"
  s.description  = "An extraction of the Melrbourne Ruby 1.8 and 1.9 parser and AST from Rubinius"

  s.files        = %w[LICENSE README.md Rakefile] + `git ls-files ext lib`.split("\n")
  s.extensions   = ["ext/melbourne/extconf.rb"]
  s.platform     = Gem::Platform::RUBY
  s.require_path = 'lib'
end
