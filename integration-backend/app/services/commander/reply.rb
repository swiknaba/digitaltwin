# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    # Posts the Commander's reply to an active request's source thread once and
    # completes the request. Replaying the same text after completion returns
    # "queued" again; a changed text is rejected.
    class Reply
      extend T::Sig

      Code = Dto::ErrorCode
      State = Domains::Commander::Dto::CommanderRequestState
      Messaging = Domains::Messaging
      Outcome = T.type_alias { Kirei::Services::Result[String] }
      QUEUED = "queued"

      sig do
        params(authorize: AuthorizeRequest, requests: Domains::Commander::CommanderRequests, inbox: Messaging::Inbox, outbox: Messaging::Outbox,
               lock: Platform::Lock, transaction: Platform::Transaction).void
      end
      def initialize(authorize:, requests: Domains::Commander::CommanderRequests.new, inbox: Messaging::Inbox.new, outbox: Messaging::Outbox.new,
                     lock: Platform::Lock.new, transaction: Platform::Transaction.new)
        @authorize = authorize
        @requests = requests
        @inbox = inbox
        @outbox = outbox
        @lock = lock
        @transaction = transaction
      end

      sig { params(request_id: String, token: String, text: String).returns(Outcome) }
      def call(request_id:, token:, text:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          authorized = @authorize.call(id: request_id, token: token, states: [State::Active, State::Complete])
          next Kirei::Services::Result.new(errors: authorized.errors) if authorized.failed?
          next failure(Code::InvalidReply, "Invalid Commander reply") unless text.bytesize.between?(1, 60_000)

          id = authorized.result.id
          @lock.call(key: "commander") { @transaction.call { reply(id, text) } }
        rescue Platform::Lock::Busy => error
          failure(Code::Busy, error.message)
        rescue Adapters::Mattermost::Errors::RequestFailed => error
          failure(Code::ChatRequestFailed, error.message)
        end
      end

      sig { params(id: String, text: String).returns(Outcome) }
      private def reply(id, text)
        row = T.must(@requests.lock(id: id))
        key = "commander:reply:#{id}"
        if row.state == State::Complete
          receipt = @outbox.item_by_key(key: key)
          return failure(Code::ReplyChanged, "Changed or recovered reply") unless receipt && receipt.body == text

          return Kirei::Services::Result.new(result: QUEUED)
        end
        return failure(Code::AlreadyCompleted, "Request already completed") unless row.state == State::Active

        source = T.must(@inbox.find(id: row.inbox_id))
        message = Messaging::Dto::OutgoingMessage.new(
          channel_id: source.channel_id,
          thread_id: source.thread_id,
          bot: Messaging::Dto::Bot::Agent,
          role: Messaging::Dto::SpeakerRole::Commander,
          body: text,
          key: key
        )
        Platform::Unwrap.call(@outbox.enqueue(message: message))
        @requests.mark(id: id, state: State::Complete)
        Kirei::Services::Result.new(result: QUEUED)
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
