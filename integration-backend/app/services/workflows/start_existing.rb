# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Handles workflow.start: an exact `@agent start` root post by default in an enrolled
    # project channel starts a workflow in that same thread.
    class StartExisting
      extend T::Sig
      include Platform::Jobs::Handler

      Code = Dto::ErrorCode
      Commands = ::Services::Commands
      Outcome = T.type_alias { Kirei::Services::Result[String] }

      sig do
        params(source: Domains::Messaging::VerifyHumanSource, request_start: RequestStart, commander_handle: String, agent_handle: String,
               directory: Domains::Projects::Directory).void
      end
      def initialize(source:, request_start:, commander_handle:, agent_handle:, directory: Domains::Projects::Directory.new)
        @source = source
        @request_start = request_start
        @directory = directory
        @commander = commander_handle
        @agent = agent_handle
      end

      # Failures raise, so the worker keeps today's retry path.
      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          Platform::Unwrap.call(start(Domains::Commander::Dto::InboxDispatchJob.from_hash(job.payload, true).inbox_id))
          Platform::Jobs::Dto::Decision.complete
        end
      end

      sig { params(inbox_id: String).returns(Outcome) }
      private def start(inbox_id)
        verified = @source.call(inbox_id: inbox_id)
        return Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

        delivery = verified.result
        command = Commands::Parser.new.call(body: delivery.body, commander_handle: @commander, agent_handle: @agent)
        start = command.is_a?(Commands::Dto::AgentCommand) && command.action == Commands::Dto::AgentAction::Start && command.single_space_separator
        return failure(Code::StartRequired, "Human root start required") unless delivery.root_post && start

        project = @directory.for_channel(channel_id: delivery.channel_id)
        return failure(Code::ProjectMappingRequired, "Use verified project mapping through Commander") unless project

        @request_start.call(inbox_id: inbox_id, project_id: project.id, title: delivery.body, existing_thread: delivery.thread_id)
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
