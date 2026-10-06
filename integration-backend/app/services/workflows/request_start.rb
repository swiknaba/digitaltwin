# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Records a verified human start request and queues its provisioning.
    # A replay from the same inbox record with the same parameters returns the
    # same request; changed parameters fail.
    class RequestStart
      extend T::Sig

      Code = Dto::ErrorCode
      Messaging = Domains::Messaging
      Workflows = Domains::Workflows
      Outcome = T.type_alias { Kirei::Services::Result[String] }

      sig do
        params(source: Messaging::VerifyHumanSource, roles: T.nilable(Workflows::Dto::RoleAssignments), directory: Domains::Projects::Directory,
               requests: Workflows::Requests, policy: Workflows::Policy, inbox: Messaging::Inbox, outbox: Messaging::Outbox, jobs: Platform::Jobs::Store).void
      end
      def initialize(source:, roles:, directory: Domains::Projects::Directory.new, requests: Workflows::Requests.new, policy: Workflows::Policy.new,
                     inbox: Messaging::Inbox.new, outbox: Messaging::Outbox.new, jobs: Platform::Jobs::Store.new)
        @source = source
        @roles = roles
        @directory = directory
        @requests = requests
        @policy = policy
        @inbox = inbox
        @outbox = outbox
        @jobs = jobs
      end

      sig { params(inbox_id: String, project_id: String, title: String, existing_thread: T.nilable(String)).returns(Outcome) }
      def call(inbox_id:, project_id:, title:, existing_thread: nil)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          project = @directory.find(id: project_id)
          next failure(Code::UnknownProject, "Unknown project") unless project

          verified = @source.call(inbox_id: inbox_id, destination: project.channel_id)
          next Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

          delivery = verified.result
          next failure(Code::InvalidTitle, "Invalid title") unless title.bytesize.between?(1, 1000)
          if existing_thread && (delivery.channel_id != project.channel_id || delivery.thread_id != existing_thread || !delivery.root_post)
            next failure(Code::UnverifiedExistingThread, "Existing thread must be verified human source")
          end

          roles = @roles
          next failure(Code::RolesMissing, "Role configuration missing") unless roles
          next failure(Code::DiversityRequired, "Writer/reviewer diversity required") unless @policy.diverse?(roles.writer, roles.reviewer)

          parameters = Workflows::Dto::RequestParameters.new(title: title, existing_thread: existing_thread, roles: roles)
          record(inbox_id, project_id, parameters, delivery)
        end
      end

      sig { params(inbox_id: String, project_id: String, parameters: Workflows::Dto::RequestParameters, delivery: Messaging::Dto::VerifiedDelivery).returns(Outcome) }
      private def record(inbox_id, project_id, parameters, delivery)
        # The digest input keeps today's JSON: [project_id, {title, existing_thread, roles}].
        digest = Digest::SHA256.hexdigest(JSON.generate([project_id, parameters.serialize]))
        Platform::Transaction.new.call do
          @inbox.lock(id: inbox_id)
          replay = !@requests.for_inbox(inbox_id: inbox_id).nil?
          created = @requests.create(inbox_id: inbox_id, project_id: project_id, digest: digest, parameters: parameters, thread_id: parameters.existing_thread)
          next Kirei::Services::Result.new(errors: created.errors) if created.failed?

          id = created.result.id
          queue(id, delivery) unless replay
          Kirei::Services::Result.new(result: id)
        end
      end

      sig { params(id: String, delivery: Messaging::Dto::VerifiedDelivery).void }
      private def queue(id, delivery)
        @jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::WorkflowProvision, payload: Workflows::Dto::ProvisionJob.new(request_id: id), dispatch_key: "workflow:provision:#{id}")
        message = Messaging::Dto::OutgoingMessage.new(
          channel_id: delivery.channel_id, thread_id: delivery.thread_id, bot: Messaging::Dto::Bot::Agent, role: Messaging::Dto::SpeakerRole::Writer,
          body: "Workflow request #{id} queued; project thread and sessions are not yet created.", key: "workflow:request:#{id}"
        )
        # A failed notice raises and rolls back the request, as before.
        Platform::Unwrap.call(@outbox.enqueue(message: message))
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
