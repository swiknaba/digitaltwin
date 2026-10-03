# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    # Callback receipts. A key is recorded once per session generation; a
    # replay must carry the same body digest.
    class Callbacks
      extend T::Sig

      # Returns the receipt id. Callers run this in the transaction that
      # queues the callback's effect, so a failed effect rolls back the receipt.
      sig { params(session_id: String, generation: Integer, key: String, body_digest: String).returns(Kirei::Services::Result[String]) }
      def record(session_id:, generation:, key:, body_digest:)
        scope = { session_id: session_id, generation: generation, key: key }
        Entities::SessionCallback.query.insert_conflict(target: %i[session_id generation key])
                                 .insert(id: Entities::SessionCallback.generate_human_id, body_digest: body_digest, **scope)
        receipt = T.must(Entities::SessionCallback.resolve_first(Entities::SessionCallback.query.where(scope), true))
        unless receipt.body_digest == body_digest
          return Kirei::Services::Result.new(errors: Platform::Failure.call(code: Dto::ErrorCode::KeyReused, detail: "Callback key reused with changed body"))
        end

        Kirei::Services::Result.new(result: receipt.id)
      end
    end
  end
end
