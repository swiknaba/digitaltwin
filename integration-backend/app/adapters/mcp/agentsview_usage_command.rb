# typed: strict
# frozen_string_literal: true

module Adapters
  module Mcp
    module AgentsviewUsageAuthorizerInterface
      extend T::Helpers
      extend T::Sig
      interface!

      sig { abstract.params(token: String).void }
      def authorize(token:); end
    end

    module AgentsviewUsageRunnerInterface
      extend T::Helpers
      extend T::Sig
      interface!

      sig { abstract.params(environment: T::Hash[String, String], argv: T::Array[String]).returns(String) }
      def run(environment:, argv:); end
    end

    # Restricts local token reporting to one pinned executable, four agents,
    # calendar-day ranges, and a fixed local-only sync/query sequence.
    class AgentsviewUsageCommand
      extend T::Sig
      include Server::ToolGateway

      JsonObject = T.type_alias { T::Hash[String, Object] }
      Range = T.type_alias { T::Hash[String, String] }
      SourceRoots = T.type_alias { T::Array[String] }

      EXECUTABLE = "/usr/local/bin/agentsview"
      SOURCE_MACHINE = "runtime"
      TIMEOUT_SECONDS = 30
      MAX_STDOUT_BYTES = 1_048_576
      ALLOWED_AGENTS = T.let(%w[claude codex gemini opencode].freeze, T::Array[String])
      SOURCE_ROOTS = T.let(["/home/runtime/.codex/sessions", "/home/runtime/.claude/projects", "/home/runtime/.gemini", "/home/runtime/.local/share/opencode"].freeze, SourceRoots)
      MANAGED_CONFIG_PATH = "/opt/runtime/config/agentsview.toml"
      ACTIVE_CONFIG_PATH = "/home/runtime/.agentsview/config.toml"

      sig do
        params(authorizer: AgentsviewUsageAuthorizerInterface, timezone: T.nilable(String), command_runner: T.nilable(AgentsviewUsageRunnerInterface), source_roots: T.nilable(SourceRoots),
               managed_config_path: T.nilable(String), active_config_path: T.nilable(String)).void
      end
      def initialize(authorizer:, timezone: nil, command_runner: nil, source_roots: nil, managed_config_path: MANAGED_CONFIG_PATH, active_config_path: ACTIVE_CONFIG_PATH)
        @timezone = T.let(timezone || ENV.fetch("RUNTIME_USAGE_TIMEZONE", "UTC"), String)
        validate_timezone!(@timezone)
        @command_runner = T.let(command_runner, T.nilable(AgentsviewUsageRunnerInterface))
        @source_roots = T.let(source_roots || SOURCE_ROOTS, SourceRoots)
        @managed_config_path = T.let(managed_config_path, T.nilable(String))
        @active_config_path = T.let(active_config_path, T.nilable(String))
        @authorizer = T.let(authorizer, AgentsviewUsageAuthorizerInterface)
      end

      sig { override.returns(T::Array[JsonObject]) }
      def definitions
        [{
          "name" => "get_usage",
          "description" => "Read local AgentsView token totals and cost for one calendar range without exposing session content.",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "range" => {
                "type" => "object",
                "description" => "Exactly one of today:true, current_month:true, last_days:1..90, or dates:{from,to}.",
                "additionalProperties" => false
              },
              "agent" => { "type" => "string", "enum" => ALLOWED_AGENTS }
            },
            "required" => ["range"],
            "additionalProperties" => false
          }
        }]
      end

      sig { override.params(name: String, args: JsonObject, token: String).returns(Object) }
      def call(name, args, token:)
        raise ArgumentError, "Unknown usage tool" unless name == "get_usage"
        raise ArgumentError, "Empty Commander request capability" if token.empty?
        raise ArgumentError, "Unexpected usage tool fields" unless [%w[range], %w[agent range]].include?(args.keys.sort)

        @authorizer.authorize(token: token)
        range = resolve_range(object(args, "range"))
        agent = optional_agent(args["agent"])
        ensure_managed_config!
        ensure_source_roots!
        run!(%w[sync])
        output = run!(usage_arguments(range, agent))
        document = parse_document(output)
        AgentsviewUsageResponse.call(document: document, range: range, agent: agent, source_machine: SOURCE_MACHINE)
      end

      sig { params(value: Object).returns(T.nilable(String)) }
      private def optional_agent(value)
        return nil if value.nil?

        raise ArgumentError, "Unsupported usage agent" unless value.is_a?(String) && ALLOWED_AGENTS.include?(value)

        value
      end

      sig { params(range: JsonObject).returns(Range) }
      private def resolve_range(range)
        raise ArgumentError, "Expected exactly one calendar range" unless range.length == 1

        key, value = range.first
        case key
        when "today"
          raise ArgumentError, "Expected today:true" unless value == true

          today_range("today")
        when "current_month"
          raise ArgumentError, "Expected current_month:true" unless value == true

          today = local_today
          { "kind" => "current_month", "from" => Date.new(today.year, today.month, 1).iso8601, "to" => today.iso8601, "timezone" => @timezone }
        when "last_days"
          raise ArgumentError, "Expected last_days between 1 and 90" unless value.is_a?(Integer) && value.between?(1, 90)

          today = local_today
          { "kind" => "last_days", "from" => (today - (value - 1)).iso8601, "to" => today.iso8601, "timezone" => @timezone }
        when "dates"
          dates_range(value)
        else
          raise ArgumentError, "Unsupported usage range"
        end
      end

      sig { params(kind: String).returns(Range) }
      private def today_range(kind)
        today = local_today.iso8601
        { "kind" => kind, "from" => today, "to" => today, "timezone" => @timezone }
      end

      sig { params(value: Object).returns(Range) }
      private def dates_range(value)
        dates = object_value(value)
        raise ArgumentError, "Expected dates from and to only" unless dates.keys.sort == %w[from to]

        from = iso_date(dates, "from")
        to = iso_date(dates, "to")
        raise ArgumentError, "Expected from on or before to" if from > to

        { "kind" => "dates", "from" => from.iso8601, "to" => to.iso8601, "timezone" => @timezone }
      end

      sig { returns(Date) }
      private def local_today
        original_timezone = ENV["TZ"]
        ENV["TZ"] = @timezone
        Date.today
      ensure
        ENV["TZ"] = original_timezone
      end

      sig { params(args: JsonObject, key: String).returns(Date) }
      private def iso_date(args, key)
        value = args.fetch(key)
        raise ArgumentError, "Expected ISO local date" unless value.is_a?(String) && /\A\d{4}-\d{2}-\d{2}\z/.match?(value)

        Date.iso8601(value)
      rescue Date::Error
        raise ArgumentError, "Expected ISO local date"
      end

      sig { params(range: Range, agent: T.nilable(String)).returns(T::Array[String]) }
      private def usage_arguments(range, agent)
        args = ["usage", "daily", "--json", "--offline", "--no-sync", "--breakdown", "--timezone", @timezone, "--since", range.fetch("from"), "--until", range.fetch("to")]
        args += ["--agent", agent] if agent
        args
      end

      sig { params(args: T::Array[String]).returns(String) }
      private def run!(args)
        environment = {
          "AGENTSVIEW_NO_DAEMON" => "1",
          "AGENTSVIEW_DATA_DIR" => "/home/runtime/.agentsview",
          "CLAUDE_PROJECTS_DIR" => "/home/runtime/.claude/projects",
          "CODEX_SESSIONS_DIR" => "/home/runtime/.codex/sessions",
          "GEMINI_DIR" => "/home/runtime/.gemini",
          "OPENCODE_DIR" => "/home/runtime/.local/share/opencode"
        }
        return @command_runner.run(environment: environment, argv: [EXECUTABLE] + args) if @command_runner

        command = T.let([EXECUTABLE] + args, T::Array[String])
        stdout, _stderr, status = Timeout.timeout(TIMEOUT_SECONDS) { Open3.capture3(environment, command) }
        raise ArgumentError, "AgentsView output exceeds the safe limit" if stdout.bytesize > MAX_STDOUT_BYTES
        raise ArgumentError, "AgentsView usage is unavailable" unless status.success?

        stdout
      rescue Timeout::Error
        raise ArgumentError, "AgentsView usage timed out"
      end

      sig { params(output: String).returns(JsonObject) }
      private def parse_document(output)
        raise ArgumentError, "AgentsView output exceeds the safe limit" if output.bytesize > MAX_STDOUT_BYTES

        parsed = JSON.parse(output)
        document = object_value(parsed)
        version = document.fetch("schema_version")
        raise ArgumentError, "Unsupported AgentsView usage schema" unless version == AgentsviewUsageResponse::EXPECTED_SCHEMA_VERSION

        document
      rescue JSON::ParserError, KeyError
        raise ArgumentError, "AgentsView returned invalid usage data"
      end

      sig { params(value: Object).returns(JsonObject) }
      private def object_value(value)
        raise ArgumentError, "Expected JSON object" unless value.is_a?(Hash)

        result = T.let({}, JsonObject)
        value.each do |key, item|
          raise ArgumentError, "Expected JSON string keys" unless key.is_a?(String)

          result[key] = item
        end
        result
      end

      sig { params(args: JsonObject, key: String).returns(JsonObject) }
      private def object(args, key)
        object_value(args.fetch(key))
      end

      sig { void }
      private def ensure_managed_config!
        return unless @managed_config_path && @active_config_path

        expected = File.binread(@managed_config_path)
        active = File.binread(@active_config_path)
        raise ArgumentError, "AgentsView managed configuration was changed" unless active == expected
      rescue Errno::ENOENT, Errno::EACCES
        raise ArgumentError, "AgentsView managed configuration is unavailable"
      end

      sig { void }
      private def ensure_source_roots!
        valid = @source_roots.all? { |path| File.directory?(path) && File.realpath(path) == path }
        raise ArgumentError, "AgentsView source roots are unavailable" unless valid
      end

      sig { params(timezone: String).void }
      private def validate_timezone!(timezone)
        parts = timezone.split("/")
        valid_parts = !parts.empty? && parts.none? { |part| %w[. ..].include?(part) } && parts.all? { |part| /\A[A-Za-z0-9_+.-]+\z/.match?(part) }
        path = "/usr/share/zoneinfo/#{parts.join("/")}"
        raise ArgumentError, "RUNTIME_USAGE_TIMEZONE must be an IANA timezone" unless valid_parts && File.file?(path)
      end
    end
  end
end
