# frozen_string_literal: true

module Domains
  module Controller
    class Tools
      DEFINITIONS = {
        "list_projects" => {}, "list_workflows" => {}, "read_context" => {},
        "start_workflow" => { "project_id" => "string", "title" => "string" },
        "send_prompt" => { "workflow_id" => "string", "evidence_inbox_ids" => "array" },
        "workflow_control" => { "workflow_id" => "string", "action" => "string", "expected_version" => "integer" }
      }.freeze
      def initialize(db, services:, requests:)
        @db, @services, @requests = db, services, requests
      end

      def definitions
        DEFINITIONS.map do |name, fields|
          properties = fields.transform_values { |type| type == "array" ? { "type" => "array", "items" => { "type" => "integer" }, "maxItems" => 10 } : { "type" => type } }.merge("request_id" => { "type" => "string" })
          { "name" => name, "description" => "Verified request-bound #{name.tr('_', ' ')}", "inputSchema" => { "type" => "object", "properties" => properties, "required" => properties.keys, "additionalProperties" => false } }
        end
      end

      def call(name, args, token:)
        fields = DEFINITIONS.fetch(name)
        raise ArgumentError, "Unexpected tool fields" unless args.keys.sort == (fields.keys + ["request_id"]).sort
        raise ArgumentError, "Invalid tool arguments" unless fields.all? { |key, type| args[key].is_a?(type == "integer" ? Integer : type == "array" ? Array : String) }

        r = @requests.authorize(args.fetch("request_id"), token)
        if args.key?("evidence_inbox_ids")
          ids = args["evidence_inbox_ids"]
          raise ArgumentError, "Invalid evidence IDs" unless ids.size.between?(1, 10) && ids.all? { |id| id.is_a?(Integer) && id.positive? }
        end
        case name
        when "list_projects"
          @db[:projects].all.select { |p| @services.source.human(r[:inbox_id], destination: p[:channel_id]) rescue false }.map { |p| p.slice(:id, :slug, :channel_id) }
        when "list_workflows"
          @db[:workflows].where(archived_at: nil).all.select { |w| @services.source.human(r[:inbox_id], destination: w[:channel_id]) rescue false }.map { |w| w.slice(:id, :project_id, :channel_id, :thread_id, :phase, :version, :artifacts, :source_inbox_id) }
        when "read_context"
          @db[:inbox].where { created_at > Time.now - 1800 }.order(Sequel.desc(:id)).limit(10).all.filter_map do |row|
            begin
              @services.source.human(r[:inbox_id], destination: row[:channel_id])
              d = @services.source.human(row[:id])
              { "inbox_id" => row[:id], "channel_id" => d.channel_id, "thread_id" => d.thread_id, "text" => d.body }
            rescue ArgumentError
              nil
            end
          end
        when "start_workflow"
          { "request_id" => @services.provision.request(inbox_id: r[:inbox_id], project_id: args["project_id"], title: args["title"]) }
        when "send_prompt"
          # A model may propose a workflow based on real conversation evidence;
          # an unbound selection still needs a human clarification command.
          @services.routing.route(inbox_id: r[:inbox_id], interpretation: { "workflow_id" => args["workflow_id"], "evidence_inbox_ids" => args["evidence_inbox_ids"] })
        when "workflow_control"
          raise ArgumentError, "Unsupported control" unless %w[pause resume finish cancel].include?(args["action"])

          w = @db[:workflows][id: args["workflow_id"]] or raise ArgumentError, "Missing workflow"
          @services.source.human(r[:inbox_id], destination: w[:channel_id])
          raise ArgumentError, "Workflow version changed" unless w[:version] == args["expected_version"]

          payload = { "inbox_id" => r[:inbox_id], "workflow_id" => w[:id], "action" => args["action"], "expected_version" => args["expected_version"] }
          Domains::Jobs::Store.new(@db).enqueue(kind: "master.control", payload: payload, key: "master:control:#{r[:id]}:#{w[:id]}:#{args['action']}:#{w[:version]}")
          { "status" => "queued" }
        end
      end
    end
  end
end
