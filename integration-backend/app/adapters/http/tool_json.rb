# typed: strict
# frozen_string_literal: true

module Adapters
  module Http
    # Serializes a typed Master tool response to the tool's JSON value. Field
    # names, order and nulls are the wire contract of /internal/master/tools.
    class ToolJson
      extend T::Sig

      Responses = Services::Master::Dto
      JsonObject = T.type_alias { T::Hash[String, Object] }
      JsonValue = T.type_alias { T.any(JsonObject, T::Array[JsonObject]) }

      sig { params(response: Responses::ToolResponse).returns(JsonValue) }
      def self.call(response)
        case response
        when Responses::ProjectList
          response.projects.map { |project| { "id" => project.id, "slug" => project.slug, "channel_id" => project.channel_id } }
        when Responses::WorkflowList
          response.workflows.map { |workflow| workflow(workflow) }
        when Responses::ContextList
          response.entries.map { |entry| { "inbox_id" => entry.inbox_id, "channel_id" => entry.channel_id, "thread_id" => entry.thread_id, "text" => entry.text } }
        when Responses::StartReceipt
          { "request_id" => response.request_id }
        when Responses::RouteOutcome
          followup = response.followup
          followup ? followup(followup) : { "status" => "clarification" }
        when Responses::ControlReceipt
          { "status" => response.status }
        else
          T.absurd(response)
        end
      end

      sig { params(workflow: Domains::Workflows::Dto::WorkflowView).returns(JsonObject) }
      private_class_method def self.workflow(workflow)
        { "id" => workflow.id, "project_id" => workflow.project_id, "channel_id" => workflow.channel_id, "thread_id" => workflow.thread_id,
          "phase" => workflow.phase.serialize, "version" => workflow.version, "artifacts" => workflow.artifacts.serialize, "source_inbox_id" => workflow.source_inbox_id }
      end

      # Times stay Time values: the JSON encoder writes them as Time#to_s.
      sig { params(followup: Domains::Commander::Dto::FollowupView).returns(JsonObject) }
      private_class_method def self.followup(followup)
        { "id" => followup.id, "inbox_id" => followup.inbox_id, "workflow_id" => followup.workflow_id, "session_id" => followup.session_id,
          "generation" => followup.generation, "status" => followup.status.serialize, "reason" => followup.reason, "evidence" => followup.evidence.serialize,
          "created_at" => followup.created_at, "delivered_at" => followup.delivered_at }
      end
    end
  end
end
