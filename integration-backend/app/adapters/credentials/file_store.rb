# typed: strict
# frozen_string_literal: true

module Adapters
  module Credentials
    # Session and request token files under one root. The root is mode 0700
    # and must not be a symlink. New files are mode 0600 and created with
    # File::EXCL, so an existing file or symlink is never overwritten.
    class FileStore
      extend T::Sig

      NAME = T.let(/\A[A-Za-z0-9_-][A-Za-z0-9_.-]*\z/, Regexp)

      sig { params(root: String).void }
      def initialize(root:)
        @root = root
      end

      sig { params(name: String).returns(String) }
      def path(name:)
        raise ArgumentError, "Invalid credential name" unless name.match?(NAME)

        File.join(@root, name)
      end

      sig { params(name: String, token: String).returns(String) }
      def write(name:, token:)
        target = path(name: name)
        FileUtils.mkdir_p(@root, mode: 0o700)
        raise ArgumentError, "Credential root symlink" if File.symlink?(@root)

        File.open(target, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(token) }
        target
      end

      sig { params(name: String).returns(String) }
      def read(name:)
        target = path(name: name)
        raise ArgumentError, "Credential root symlink" if File.symlink?(@root)
        raise ArgumentError, "Credential file symlink" if File.symlink?(target)

        File.read(target)
      end

      sig { params(name: String).void }
      def delete(name:)
        FileUtils.rm_f(path(name: name))
      end
    end
  end
end
