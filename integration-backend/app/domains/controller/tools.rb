# typed: strict
# frozen_string_literal: true

module Domains
  module Controller
    class Tools
      extend T::Sig

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
        @db = T.let(db, Sequel::Database)
        @services = T.let(services, Services)
        @requests = T.let(requests, Requests)
      end

      sig { returns(T::Array[T::Hash[String, Object]]) }
      def definitions
        DEFINITIONS.map do |name, fields|
          properties = fields.transform_values { |type| type == "array" ? { "type" => "array", "items" => { "type" => "integer" }, "maxItems" => 10 } : { "type" => type } }.merge("request_id" => { "type" => "string" })
          { "name" => name, "description" => "Verified request-bound #{name.tr("_", " ")}", "inputSchema" => { "type" => "object", "properties" => properties, "required" => properties.keys, "additionalProperties" => false } }
        end
      end

      sig { params(name: String, args: ToolArguments, token: String).returns(Object) }
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
          @db[:projects].all.select { |p| @services.source.human(request_inbox_id(r), destination: p[:channel_id]) rescue false }.map { |p| p.slice(:id, :slug, :channel_id) }
        when "list_workflows"
          @db[:workflows].where(archived_at: nil).all.select { |w| @services.source.human(request_inbox_id(r), destination: w[:channel_id]) rescue false }.map { |w| w.slice(:id, :project_id, :channel_id, :thread_id, :phase, :version, :artifacts, :source_inbox_id) }
        when "read_context"
          @db[:inbox].where(Sequel[:inbox][:created_at] > Time.now - 1800).order(Sequel.desc(:id)).limit(10).all.filter_map do |row|
            begin
              @services.source.human(request_inbox_id(r), destination: row[:channel_id])
              d = @services.source.human(row[:id])
              { "inbox_id" => row[:id], "channel_id" => d.channel_id, "thread_id" => d.thread_id, "text" => d.body }
            rescue ArgumentError
              nil
            end
          end
        when "start_workflow"
          { "request_id" => @services.provision.request(inbox_id: request_inbox_id(r).to_s, project_id: required_string(args, "project_id"), title: required_string(args, "title")) }
        when "send_prompt"
          # A model may propose a workflow based on real conversation evidence;
          # an unbound selection still needs a human clarification command.
          @services.routing.route(inbox_id: request_inbox_id(r), interpretation: { "workflow_id" => required_string(args, "workflow_id"), "evidence_inbox_ids" => evidence_ids(args) })
        when "workflow_control"
          raise ArgumentError, "Unsupported control" unless %w[pause resume finish cancel].include?(args["action"])

          w = @db[:workflows][id: args["workflow_id"]] or raise ArgumentError, "Missing workflow"
          @services.source.human(request_inbox_id(r), destination: w[:channel_id])
          raise ArgumentError, "Workflow version changed" unless w[:version] == args["expected_version"]

          payload = { "inbox_id" => r[:inbox_id], "workflow_id" => w[:id], "action" => args["action"], "expected_version" => args["expected_version"] }
          Domains::Jobs::Store.new(@db).enqueue(kind: "master.control", payload: payload, key: "master:control:#{r[:id]}:#{w[:id]}:#{args["action"]}:#{w[:version]}")
          { "status" => "queued" }
        end
      end

      private

      sig { params(args: ToolArguments, key: String).returns(String) }
      def required_string(args, key)
        value = args.fetch(key) { raise ArgumentError, "Missing #{key}" }
        raise ArgumentError, "Invalid #{key}" unless value.is_a?(String)

        value
      end

      sig { params(args: ToolArguments).returns(T::Array[Integer]) }
      def evidence_ids(args)
        value = args.fetch("evidence_inbox_ids") { raise ArgumentError, "Missing evidence IDs" }
        raise ArgumentError, "Invalid evidence IDs" unless value.is_a?(Array)

        ids = value.select { |id| id.is_a?(Integer) && id.positive? }
        raise ArgumentError, "Invalid evidence IDs" unless ids.size == value.size && ids.size.between?(1, 10)

        ids
      end

      sig { params(request: Requests::RequestRow).returns(T.any(Integer, String)) }
      def request_inbox_id(request)
        value = request.fetch(:inbox_id)
        raise ArgumentError, "Invalid request capability" unless value.is_a?(Integer) || value.is_a?(String)

        value
      end
    end
  end
end
