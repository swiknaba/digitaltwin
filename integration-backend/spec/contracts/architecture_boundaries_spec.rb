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
    "app/adapters/mattermost/api.rb",
    "app/adapters/mattermost/delivery_verifier.rb",
    "app/adapters/herdr/client.rb",
    "app/adapters/http/*",
    "app/adapters/mcp/*",
    "app/platform/json/scalars.rb",
    "app/platform/jobs/entities/*",
    "app/platform/audit/entities/*"
  ].freeze

  # Ruling 22: adapters may implement these domain ports (interface! modules).
  port_constants = ["Domains::Messaging::DeliveryVerifier", "Domains::Messaging::MembershipCheck"].freeze

  layer_namespaces = { "domains" => "Domains", "services" => "Services", "adapters" => "Adapters", "platform" => "Platform" }.freeze
  # The lookbehind skips gem namespaces such as Kirei::Services::Result but
  # keeps root-anchored references such as ::Services::Commands::Parser.
  reference_pattern = /(?<!\w::)\b(Domains|Services|Adapters|Platform)::(\w+)(?:::(\w+))?/
  raw_table_pattern = /\b(?:@?db|raw_db_connection)\[:|Sequel\.lit/
  broad_signature_pattern = /returns\(Object\)|T::Hash\[(?:Symbol|String), Object\]|T\.untyped|T\.unsafe/
  entity_pattern = /\b(Domains|Platform)::(\w+)::Entities/
  raw_connection_pattern = /raw_db_connection/
  advisory_lock_pattern = /pg_(try_)?advisory/
  # Kirei has no advisory-lock or cross-model transaction API (Ruling 5).
  raw_connection_owners = ["app/platform/lock.rb", "app/platform/transaction.rb"].freeze
  advisory_lock_owners = ["app/platform/lock.rb"].freeze

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
      port = ref_layer == "Domains" && port_constants.include?("Domains::#{ref_context}::#{ref_member}")
      ref_layer == "Platform" || own_context || dto_reference || port || (transport && ref_layer == "Services")
    when "services"
      !((ref_layer == "Domains" || ref_layer == "Platform") && ref_member == "Entities")
    else
      false
    end
  end

  # Whether one code line in `path` violates `rule`.
  line_offends = lambda do |rule, path, line|
    layer, context = layer_and_context.call(path)
    case rule
    when "raw_table_access"
      line.match?(raw_table_pattern)
    when "broad_signatures"
      line.match?(broad_signature_pattern) && boundary_files.none? { |glob| File.fnmatch?(glob, path) }
    when "raw_db_connection"
      line.match?(raw_connection_pattern) && !raw_connection_owners.include?(path)
    when "advisory_locks"
      line.match?(advisory_lock_pattern) && !advisory_lock_owners.include?(path)
    when "private_entities"
      line.scan(entity_pattern).any? { |ref_layer, name| !path.start_with?("app/#{ref_layer.downcase}/#{snake.call(name)}/") }
    when "layer_dependencies"
      line.scan(reference_pattern).any? do |ref_layer, ref_context, ref_member|
        !allowed_reference.call(layer, context, ref_layer, ref_context, ref_member)
      end
    else
      raise ArgumentError, "unknown rule #{rule}"
    end
  end

  # Maps a rule name to the sorted "path:line" entries that violate it.
  violations_for = lambda do |rule|
    app_files.flat_map do |path|
      code_lines.call(path).flat_map do |line_number, line|
        line_offends.call(rule, path, line) ? ["#{path}:#{line_number}"] : []
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
    "keeps the raw database connection inside Platform::Lock and Platform::Transaction" => "raw_db_connection",
    "keeps advisory locks inside Platform::Lock" => "advisory_locks",
    "enforces layer dependencies" => "layer_dependencies"
  }.each do |description, rule|
    it description do
      unexpected, stale = audit.call(rule)

      expect(unexpected).to be_empty, "#{rule} violations not in the allowlist:\n#{unexpected.join("\n")}"
      expect(stale).to be_empty, "#{rule} allowlist entries that no longer violate (remove them):\n#{stale.join("\n")}"
    end
  end

  it "scans root-anchored references, skips gem namespaces, and allows declared adapter ports" do
    domain_file = "app/domains/projects/catalog.rb"
    adapter_file = "app/adapters/mattermost/api.rb"
    flagged = ->(path, line) { line_offends.call("layer_dependencies", path, line) }

    expect(flagged.call(domain_file, "::Services::Commands::Parser.new")).to be(true)
    expect(flagged.call(domain_file, "Services::Commands::Parser.new")).to be(true)
    expect(flagged.call(domain_file, "Kirei::Services::Result.new(result: x)")).to be(false)
    expect(line_offends.call("private_entities", domain_file, "::Domains::Messaging::Entities::InboxEntry")).to be(true)
    expect(flagged.call(adapter_file, "include Domains::Messaging::MembershipCheck")).to be(false)
    expect(flagged.call(adapter_file, "Domains::Messaging::Outbox.new")).to be(true)
  end
end
