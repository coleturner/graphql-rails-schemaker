# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'graphql/rails/schemaker/version'

Gem::Specification.new do |spec|
  spec.name          = "graphql-rails-schemaker"
  spec.version       = Graphql::Rails::Schemaker::VERSION
  spec.date          = Date.today.to_s
  spec.authors       = ["Cole Turner"]
  spec.email         = ["turner.cole@gmail.com"]

  spec.summary       = ""
  spec.homepage      = "https://github.com/colepatrickturner/graphql-rails-schemaker"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "graphql", ">= 0.19.0"
  spec.add_development_dependency "bundler", "~> 1.13"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.required_ruby_version = '>= 2.2.2'
end
