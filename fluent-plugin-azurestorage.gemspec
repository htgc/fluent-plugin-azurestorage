# encoding: utf-8
$:.push File.expand_path('../lib', __FILE__)

Gem::Specification.new do |gem|
  gem.name        = "fluent-plugin-azurestorage"
  gem.description = "Azure Storage output plugin for Fluentd event collector"
  gem.license     = "Apache-2.0"
  gem.homepage    = "https://github.com/gintau/fluent-plugin-azurestorage"
  gem.summary     = gem.description
  gem.version     = File.read("VERSION").strip
  gem.authors     = ["Hidemasa Togashi"]
  gem.email       = ["togachiro@gmail.com"]
  #gem.platform    = Gem::Platform::RUBY
  gem.files       = `git ls-files`.split("\n")
  gem.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.require_paths = ['lib']

  gem.add_dependency "fluentd", [">= 0.14.0", "< 2"]
  gem.add_dependency "azure", [">= 0.7.1", "<= 0.7.10"]
  gem.add_dependency "uuidtools", ">= 2.1.5"
  gem.add_development_dependency "rake", ">= 0.9.2"
  gem.add_development_dependency "test-unit", ">= 3.0.8"
  gem.add_development_dependency "test-unit-rr", ">= 1.0.3"
end
