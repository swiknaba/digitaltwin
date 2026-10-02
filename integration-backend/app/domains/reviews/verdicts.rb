# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    # Records a round's reviewer verdict. A verdict proves that the reviewer
    # received the prompt, so it also marks the dispatch delivered. Each round
    # is decided once.
    class Verdicts
      extend T::Sig

      sig { params(rounds: Rounds).void }
      def initialize(rounds: Rounds.new)
        @rounds = rounds
      end

      sig { params(review_id: String, review_commit: String, verdict: Dto::Verdict).returns(Kirei::Services::Result[Dto::ReviewView]) }
      def record(review_id:, review_commit:, verdict:)
        review = @rounds.find(id: review_id)
        return failure(Dto::ErrorCode::MissingReview, Rounds::MALFORMED) unless review
        return failure(Dto::ErrorCode::AlreadyDecided, "Review already decided") if review.verdict

        # The verdict condition keeps a concurrent decision from being overwritten.
        updated = Entities::Review.query.where(id: review_id, verdict: nil)
                                  .update(review_commit: review_commit, verdict: verdict.serialize, dispatch_state: Dto::DispatchState::Delivered.serialize)
        return failure(Dto::ErrorCode::AlreadyDecided, "Review already decided") unless updated == 1

        Kirei::Services::Result.new(result: T.must(@rounds.find(id: review_id)))
      end

      sig { params(code: Dto::ErrorCode, detail: String).returns(Kirei::Services::Result[Dto::ReviewView]) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
