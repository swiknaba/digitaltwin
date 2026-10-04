# typed: strict
# frozen_string_literal: true

module Adapters
  module Memory
    # Atomically rewrites only the backend-managed section of a durable memory
    # file. Text outside the markers remains user-owned and unchanged.
    class FileStore
      extend T::Sig

      START = "<!-- digitaltwin-memory:start -->"
      FINISH = "<!-- digitaltwin-memory:end -->"

      sig { params(path: String, entries: T::Array[Domains::Memory::Dto::MemoryEntry]).void }
      def write(path:, entries:)
        FileUtils.mkdir_p(File.dirname(path))
        raise Errors::WriteFailed, "Memory file is a symlink" if File.symlink?(path)

        existing = File.exist?(path) ? File.read(path) : ""
        rendered = replace(existing: existing, managed: managed(entries: entries))
        temporary = "#{path}.#{SecureRandom.uuid}.tmp"
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(rendered) }
        File.rename(temporary, path)
      rescue Errno::EACCES, Errno::EDQUOT, Errno::EIO, Errno::ENOSPC, Errno::EROFS => error
        raise Errors::WriteFailed, "Could not persist memory: #{error.class}"
      ensure
        FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
      end

      sig { params(existing: String, managed: String).returns(String) }
      private def replace(existing:, managed:)
        range = /#{Regexp.escape(START)}.*?#{Regexp.escape(FINISH)}\n?/m
        replacement = "#{START}\n#{managed}#{FINISH}\n"
        return existing.sub(range, replacement) if existing.match?(range)

        separator = existing.empty? || existing.end_with?("\n") ? "\n" : "\n\n"
        "#{existing}#{separator}#{replacement}"
      end

      sig { params(entries: T::Array[Domains::Memory::Dto::MemoryEntry]).returns(String) }
      private def managed(entries:)
        return "## Managed Commander memory\n\nNo remembered entries yet.\n" if entries.empty?

        sections = entries.map do |entry|
          project = entry.project_id ? " project #{entry.project_id}" : ""
          "### #{entry.id} (revision #{entry.revision}, source #{entry.source}#{project})\n\n#{entry.content.strip}\n"
        end
        "## Managed Commander memory\n\n#{sections.join("\n")}"
      end
    end
  end
end
