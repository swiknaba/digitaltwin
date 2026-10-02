# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    class Tools
      extend T::Sig
      include Adapters::Mcp::Server::ToolGateway

      FieldDefinitions = T.type_alias { T::Hash[String, T::Hash[String, String]] }
      ToolArguments = T.type_alias { T::Hash[String, Object] }
      DEFINITIONS = T.let({
        "list_projects" => {}, "list_workflows" => {}, "read_context" => {},
        "start_workflow" => { "project_id" => "string", "title" => "string" },
        "send_prompt" => { "workflow_id" => "string", "evidence_inbox_ids" => "array" },
        "workflow_control" => { "workflow_id" => "string", "action" => "string", "expected_version" => "integer" }
      }.freeze, FieldDefinitions)

      sig { params(db: Sequel::Database, services: Services, requests: Requests).void }
      def initialize(db, services:, requests:)
        @db = db
        @services = services
        @requests = requests
      end

      sig { override.returns(T::Array[T::Hash[String, Object]]) }
      def definitions
        DEFINITIONS.map do |name, fields|
          properties = fields.transform_values { |type| type == "array" ? { "type" => "array", "items" => { "type" => "integer" }, "maxItems" => 10 } : { "type" => type } }.merge("request_id" => { "type" => "string" })
          { "name" => name, "description" => "Verified request-bound #{name.tr("_", " ")}", "inputSchema" => { "type" => "object", "properties" => properties, "required" => properties.keys, "additionalProperties" => false } }
        end
      end

      sig { override.params(name: String, args: ToolArguments, token: String).returns(Object) }
      def call(name, args, token:)
        fields = DEFINITIONS.fetch(name)
        raise ArgumentError, "Unexpected tool fields" unless args.keys.sort == (fields.keys + ["request_id"]).sort
        raise ArgumentError, "Invalid tool arguments" unless fields.all? { |key, type| args[key].is_a?(type == "integer" ? Integer : type == "array" ? Array : String) }

        r = @requests.authorize(required_string(args, "request_id"), token)
        if args.key?("evidence_inbox_ids")
          evidence_ids(args)
        end
        case name
        when "list_projects"
          @db[:projects].all.select { |p| @services.source.call(inbox_id: request_inbox_id(r), destination: p[:channel_id]).success? rescue false }.map { |p| p.slice(:id, :slug, :channel_id) }
        when "list_workflows"
          @db[:workflows].where(archived_at: nil).all.select { |w|
            @services.source.call(inbox_id: request_inbox_id(r), destination: w[:channel_id]).success? rescue false
          }.map { |w| w.slice(:id, :project_id, :channel_id, :thread_id, :phase, :version, :artifacts, :source_inbox_id) }
        when "read_context"
          Domains::Messaging::Inbox.new.recent(since: Time.now - 1800, limit: 10).filter_map do |record|
            begin
              Platform::Unwrap.call(@services.source.call(inbox_id: request_inbox_id(r), destination: record.channel_id))
              d = Platform::Unwrap.call(@services.source.call(inbox_id: record.id))
              { "inbox_id" => record.id, "channel_id" => d.channel_id, "thread_id" => d.thread_id, "text" => d.body }
            rescue ArgumentError
              nil
            end
          end
        when "start_workflow"
          { "request_id" => @services.provision.request(inbox_id: request_inbox_id(r), project_id: required_string(args, "project_id"), title: required_string(args, "title")) }
        when "send_prompt"
          # A model may propose a workflow based on real conversation evidence;
          # an unbound selection still needs a human clarification command.
          @services.routing.route(inbox_id: request_inbox_id(r), interpretation: { "workflow_id" => required_string(args, "workflow_id"), "evidence_inbox_ids" => evidence_ids(args) })
        when "workflow_control"
          raise ArgumentError, "Unsupported control" unless %w[pause resume finish cancel].include?(args["action"])

          w = @db[:workflows][id: args["workflow_id"]] or raise ArgumentError, "Missing workflow"
          inbox_id = request_inbox_id(r)
          Platform::Unwrap.call(@services.source.call(inbox_id: inbox_id, destination: w[:channel_id]))
          raise ArgumentError, "Workflow version changed" unless w[:version] == args["expected_version"]

          payload = Dto::MasterControlJob.new(inbox_id: inbox_id, workflow_id: w[:id], action: required_string(args, "action"), expected_version: required_integer(args, "expected_version"))
          Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::MasterControl, payload: payload, dispatch_key: "master:control:#{r[:id]}:#{w[:id]}:#{args["action"]}:#{w[:version]}")
          { "status" => "queued" }
        end
      end

      sig { params(args: ToolArguments, key: String).returns(String) }
      private def required_string(args, key)
        value = args.fetch(key) { raise ArgumentError, "Missing #{key}" }
        raise ArgumentError, "Invalid #{key}" unless value.is_a?(String)

        value
      end

      sig { params(args: ToolArguments, key: String).returns(Integer) }
      private def required_integer(args, key)
        value = args.fetch(key) { raise ArgumentError, "Missing #{key}" }
        raise ArgumentError, "Invalid #{key}" unless value.is_a?(Integer)

        value
      end

      sig { params(args: ToolArguments).returns(T::Array[Integer]) }
      private def evidence_ids(args)
        value = args.fetch("evidence_inbox_ids") { raise ArgumentError, "Missing evidence IDs" }
        raise ArgumentError, "Invalid evidence IDs" unless value.is_a?(Array)

        ids = value.select { |id| id.is_a?(Integer) && id.positive? }
        raise ArgumentError, "Invalid evidence IDs" unless ids.size == value.size && ids.size.between?(1, 10)

        ids
      end

      sig { params(request: Requests::RequestRow).returns(Integer) }
      private def request_inbox_id(request)
        value = request.fetch(:inbox_id)
        raise ArgumentError, "Invalid request capability" unless value.is_a?(Integer)

        value
      end
    end
  end
end
