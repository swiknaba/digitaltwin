# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Reads one review row and types it. `reviews` has no model until Task 8,
    # so this temporary reader uses the raw dataset (allowlisted).
    class LatestReview
      extend T::Sig

      Gate = Domains::Workflows::Dto::Gate

      sig { params(db: Sequel::Database).void }
      def initialize(db)
        @db = db
      end

      # With a gate: that gate's highest round. Without one: the newest review
      # that requested changes.
      sig { params(workflow_id: String, gate: T.nilable(Gate)).returns(T.nilable(Dto::ReviewRecord)) }
      def call(workflow_id:, gate:)
        reviews = @db[:reviews]
        row = if gate
                reviews.where(workflow_id: workflow_id, gate: gate.serialize).order(Sequel.desc(:round)).first
              else
                reviews.where(workflow_id: workflow_id, verdict: "changes_requested").order(Sequel.desc(:created_at), Sequel.desc(:id)).first
              end
        return nil unless row

        Dto::ReviewRecord.new(id: text!(row[:id]), gate: text!(row[:gate]), round: integer!(row[:round]), target_commit: text!(row[:target_commit]),
                              review_commit: optional_text!(row[:review_commit]), review_path: text!(row[:review_path]), verdict: optional_text!(row[:verdict]))
      end

      # Sequel row values are untyped; BasicObject accepts them without a cast.
      sig { params(value: BasicObject).returns(String) }
      private def text!(value)
        case value
        when String then value
        else raise ArgumentError, "Malformed durable review record"
        end
      end

      sig { params(value: BasicObject).returns(T.nilable(String)) }
      private def optional_text!(value)
        case value
        when NilClass then nil
        else text!(value)
        end
      end

      sig { params(value: BasicObject).returns(Integer) }
      private def integer!(value)
        case value
        when Integer then value
        else raise ArgumentError, "Malformed durable review record"
        end
      end
    end
  end
end
