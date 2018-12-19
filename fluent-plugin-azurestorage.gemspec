# encoding: utf-8
$:.push File.expand_path('../lib', __FILE__)

Gem::Specification.new do |gem|
  gem.name        = "fluent-plugin-azurestorage"
  gem.description = "Azure Storage output plugin for Fluentd event collector"
  gem.license     = "Apache-2.0"
  gem.homepage    = "https://github.com/htgc/fluent-plugin-azurestorage"
  gem.summary     = gem.description
  gem.version     = File.read("VERSION").strip
  gem.authors     = ["Hidemasa Togashi"]
  gem.email       = ["togachiro@gmail.com"]
  #gem.platform    = Gem::Platform::RUBY
  gem.files       = `git ls-files`.split("\n")
  gem.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.require_paths = ['lib']

  gem.add_dependency "fluentd", "1.2.6"
  gem.add_dependency "azure-storage-common", "1.1.0"
  gem.add_dependency "azure-storage-blob", "1.1.0"
  gem.add_dependency "uuidtools", "2.1.5"
  gem.add_development_dependency "rake", "12.3.1"
  gem.add_development_dependency "test-unit", "3.2.8"
  gem.add_development_dependency "test-unit-rr", "1.0.5"
end
