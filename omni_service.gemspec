# frozen_string_literal: true

require_relative 'lib/omni_service/version'

Gem::Specification.new do |spec|
  spec.name = 'omni_service'
  spec.version = OmniService::VERSION
  spec.authors = ['Arkadiy Zabazhanov']
  spec.email = ['kinwizard@gmail.com']

  spec.summary = 'Composable business operations with railway-oriented programming'
  spec.description = 'Framework for building business operations as composable pipelines. ' \
    'Chain steps that short-circuit on failure, collect validation errors, ' \
    'wrap in database transactions with callbacks, and scope nested data structures.'
  spec.homepage = 'https://github.com/pyromaniac/omni_service'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*', 'LICENSE.txt', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'concurrent-ruby'
  spec.add_dependency 'dry-core'
  spec.add_dependency 'dry-initializer'
  spec.add_dependency 'dry-monads'
  spec.add_dependency 'dry-struct'
  spec.add_dependency 'dry-types'
end
