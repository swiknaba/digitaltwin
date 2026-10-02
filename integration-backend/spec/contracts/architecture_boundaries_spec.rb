# typed: strict
# frozen_string_literal: true

require "yaml"

# Statically scans app/**/*.rb. The migration allowlist lists files that still
# violate a rule and must shrink to empty; BOUNDARY_FILES is permanent.
RSpec.describe "architecture boundaries" do
  backend_root = File.expand_path("../..", __dir__)
  allowlist = YAML.safe_load_file(File.join(backend_root, "spec/contracts/architecture_allowlist.yml")) || {}

  # Exempt from the broad-signature rule only: these files translate raw JSON.
  boundary_files = [
    "app/adapters/mattermost/client.rb",
    "app/adapters/herdr/client.rb",
    "app/adapters/http/*",
    "app/adapters/mcp/*",
    "app/platform/json/scalars.rb",
    "app/platform/jobs/entities/*",
    "app/platform/audit/entities/*"
  ].freeze

  layer_namespaces = { "domains" => "Domains", "services" => "Services", "adapters" => "Adapters", "platform" => "Platform" }.freeze
  reference_pattern = /\b(Domains|Services|Adapters|Platform)::(\w+)(?:::(\w+))?/
  raw_table_pattern = /\b(?:@?db|raw_db_connection)\[:|Sequel\.lit/
  broad_signature_pattern = /returns\(Object\)|T::Hash\[(?:Symbol|String), Object\]|T\.untyped|T\.unsafe/
  entity_pattern = /\b(Domains|Platform)::(\w+)::Entities/

  camelize = ->(name) { name.split("_").map(&:capitalize).join }
  snake = ->(name) { name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase }

  # Returns [line_number, code_line] pairs, skipping full-line comments.
  code_lines = lambda do |path|
    File.readlines(File.join(backend_root, path)).each_with_index.filter_map do |line, index|
      [index + 1, line] unless line.lstrip.start_with?("#")
    end
  end

  app_files = Dir.chdir(backend_root) { Dir["app/**/*.rb"].sort }

  # Layer and context come from app/<layer>/<ctx>/...; a file directly under
  # app/<layer>/ has no context.
  layer_and_context = lambda do |path|
    segments = path.delete_prefix("app/").split("/")
    [segments.fetch(0), segments.length > 2 ? segments.fetch(1) : nil]
  end

  # Whether a file in `layer`/`context` may reference namespace `ref_layer::ref_context[::ref_member]`.
  allowed_reference = lambda do |layer, context, ref_layer, ref_context, ref_member|
    own_context = layer_namespaces.fetch(layer) == ref_layer && !context.nil? && camelize.call(context) == ref_context
    case layer
    when "platform"
      ref_layer == "Platform"
    when "domains"
      ref_layer == "Platform" || own_context || (ref_layer == "Domains" && ref_member == "Dto")
    when "adapters"
      transport = %w[http mcp].include?(context)
      dto_reference = ref_member == "Dto" && (transport || ref_layer == "Domains")
      ref_layer == "Platform" || own_context || dto_reference || (transport && ref_layer == "Services")
    when "services"
      !((ref_layer == "Domains" || ref_layer == "Platform") && ref_member == "Entities")
    else
      false
    end
  end

  # Maps a rule name to the sorted "path:line" entries that violate it.
  violations_for = lambda do |rule|
    app_files.flat_map do |path|
      layer, context = layer_and_context.call(path)
      code_lines.call(path).flat_map do |line_number, line|
        offending =
          case rule
          when "raw_table_access"
            line.match?(raw_table_pattern)
          when "broad_signatures"
            line.match?(broad_signature_pattern) && boundary_files.none? { |glob| File.fnmatch?(glob, path) }
          when "private_entities"
            line.scan(entity_pattern).any? { |layer, name| !path.start_with?("app/#{layer.downcase}/#{snake.call(name)}/") }
          when "layer_dependencies"
            line.scan(reference_pattern).any? do |ref_layer, ref_context, ref_member|
              !allowed_reference.call(layer, context, ref_layer, ref_context, ref_member)
            end
          else
            raise ArgumentError, "unknown rule #{rule}"
          end
        offending ? ["#{path}:#{line_number}"] : []
      end
    end
  end

  # Returns [violations not allowlisted, allowlist entries that no longer violate].
  audit = lambda do |rule|
    violations = violations_for.call(rule)
    allowed = allowlist.fetch(rule, [])
    unexpected = violations.reject { |entry| allowed.include?(entry.split(":").first) }
    [unexpected, allowed - violations.map { |entry| entry.split(":").first }]
  end

  {
    "forbids raw table access" => "raw_table_access",
    "forbids broad signatures" => "broad_signatures",
    "keeps entities private" => "private_entities",
    "enforces layer dependencies" => "layer_dependencies"
  }.each do |description, rule|
    it description do
      unexpected, stale = audit.call(rule)

      expect(unexpected).to be_empty, "#{rule} violations not in the allowlist:\n#{unexpected.join("\n")}"
      expect(stale).to be_empty, "#{rule} allowlist entries that no longer violate (remove them):\n#{stale.join("\n")}"
    end
  end
end
