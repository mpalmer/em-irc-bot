require 'git-version-bump'

Gem::Specification.new do |s|
	s.name = "em-irc-bot"

	s.version = GVB.version
	s.date    = GVB.date

	s.platform = Gem::Platform::RUBY

	s.homepage = "http://github.com/mpalmer/em-irc-bot"
	s.summary = "IRC bot framework for EventMachine"
	s.authors = ["Matt Palmer"]

	s.extra_rdoc_files = ["README.md"]
	s.files = `git ls-files -z`.split("\0")

	s.add_runtime_dependency "git-version-bump", "~> 0.10"
	s.add_runtime_dependency "eventmachine"

	s.add_development_dependency 'bundler'
	s.add_development_dependency 'github-release'
	s.add_development_dependency 'rake'
	s.add_development_dependency 'redcarpet'
	s.add_development_dependency 'yard'
end
