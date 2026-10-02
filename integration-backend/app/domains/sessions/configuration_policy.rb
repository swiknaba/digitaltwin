# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    # RoleConfig types the fields; this rejects empty values and NUL arguments
    # before a session is reserved with the configuration.
    class ConfigurationPolicy
      extend T::Sig

      sig { params(configuration: Workflows::Dto::RoleConfig).returns(T::Boolean) }
      def self.complete?(configuration)
        fields = [configuration.cli, configuration.provider, configuration.model, configuration.family]
        fields.none?(&:empty?) && configuration.launch_args.none? { |argument| argument.include?("\0") }
      end
    end
  end
end
