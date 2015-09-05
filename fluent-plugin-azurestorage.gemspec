# coding: utf-8
#lib = File.expand_path('../lib', __FILE__)
#$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-azurestorage"
  spec.version       = "0.0.4"
  spec.authors       = ["Hidemasa Togashi"]
  spec.email         = ["togachiro@gmail.com"]
  spec.description   = %q{Fluent plugin for store to Azure Storage}
  spec.summary       = %q{Fluent plugin for store to Azure Storage}
  spec.homepage      = ""
  spec.license       = "Apache License, version 2."

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"

  spec.add_runtime_dependency "fluentd"
  spec.add_runtime_dependency "azure", "0.6.2"
end
