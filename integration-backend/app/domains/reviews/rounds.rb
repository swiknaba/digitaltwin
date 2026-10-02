# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    # Review rounds of a workflow gate. Rounds count from 1 per gate, up to
    # MAX_ROUNDS. Callers hold the workflow's Platform::Lock. Reads fail closed
    # with Errors::MalformedRecord on a row that does not match its typed shape.
    class Rounds
      extend T::Sig

      MAX_ROUNDS = 3
      UNSETTLED_STATES = T.let(Dto::DispatchState.values.select(&:unsettled?).map(&:serialize).freeze, T::Array[String])
      MALFORMED = "Malformed durable review record"

      # Opens the gate's next round with a queued reviewer prompt. Callers run
      # it in the transaction that queues the prompt job.
      sig do
        params(workflow_id: String, gate: Workflows::Dto::Gate, target_commit: String, base_commit: T.nilable(String), review_path: String,
               reviewer: Workflows::Dto::RoleConfig).returns(Kirei::Services::Result[Dto::ReviewView])
      end
      def open(workflow_id:, gate:, target_commit:, base_commit:, review_path:, reviewer:)
        round = next_round(workflow_id: workflow_id, gate: gate)
        if round > MAX_ROUNDS
          return Kirei::Services::Result.new(errors: Platform::Failure.call(code: Dto::ErrorCode::RoundsExhausted, detail: "Review rounds exhausted"))
        end

        review = Entities::Review.create(workflow_id: workflow_id, gate: gate.serialize, round: round, target_commit: target_commit, base_commit: base_commit,
                                         review_path: review_path, reviewer_configuration: reviewer.serialize)
        Kirei::Services::Result.new(result: T.must(find(id: review.id)))
      end

      sig { params(workflow_id: String, gate: Workflows::Dto::Gate).returns(Integer) }
      def next_round(workflow_id:, gate:)
        value = gate_query(workflow_id, gate).max(:round)
        (value.is_a?(Integer) ? value : 0) + 1
      end

      sig { params(id: String).returns(T.nilable(Dto::ReviewView)) }
      def find(id:) = first(Entities::Review.query.where(id: id))

      # The round already opened for this exact artifact commit.
      sig { params(workflow_id: String, gate: Workflows::Dto::Gate, target_commit: String).returns(T.nilable(Dto::ReviewView)) }
      def find_for_target(workflow_id:, gate:, target_commit:) = first(gate_query(workflow_id, gate).where(target_commit: target_commit))

      # The round that already recorded this exact review result.
      sig { params(workflow_id: String, review_commit: String, verdict: Dto::Verdict).returns(T.nilable(Dto::ReviewView)) }
      def find_decided(workflow_id:, review_commit:, verdict:)
        first(Entities::Review.query.where(workflow_id: workflow_id, review_commit: review_commit, verdict: verdict.serialize))
      end

      # The gate's highest round.
      sig { params(workflow_id: String, gate: Workflows::Dto::Gate).returns(T.nilable(Dto::ReviewView)) }
      def latest(workflow_id:, gate:) = first(gate_query(workflow_id, gate).order(Sequel.desc(:round)))

      # The newest review of any gate that requested changes.
      sig { params(workflow_id: String).returns(T.nilable(Dto::ReviewView)) }
      def latest_changes_requested(workflow_id:)
        changes = Entities::Review.query.where(workflow_id: workflow_id, verdict: Dto::Verdict::ChangesRequested.serialize)
        first(changes.order(Sequel.desc(:created_at), Sequel.desc(:id)))
      end

      sig { params(id: String, state: Dto::DispatchState).void }
      def mark_dispatch(id:, state:)
        Entities::Review.query.where(id: id).update(dispatch_state: state.serialize)
      end

      # True when a round of these workflows has a sending or uncertain prompt.
      sig { params(workflow_ids: T::Array[String]).returns(T::Boolean) }
      def unsettled_dispatch?(workflow_ids:)
        !Entities::Review.query.where(workflow_id: workflow_ids, dispatch_state: UNSETTLED_STATES).empty?
      end

      sig { params(workflow_id: String, gate: Workflows::Dto::Gate).returns(Sequel::Dataset) }
      private def gate_query(workflow_id, gate) = Entities::Review.query.where(workflow_id: workflow_id, gate: gate.serialize)

      # T::Struct.from_hash checks neither nested types nor nested unknown
      # keys, so the reviewer configuration is rebuilt through its constructor
      # and compared with its stored form.
      sig { params(query: Sequel::Dataset).returns(T.nilable(Dto::ReviewView)) }
      private def first(query)
        entity = strictly { Entities::Review.resolve_first(query, true) }
        return nil unless entity

        Dto::ReviewView.new(
          id: entity.id, workflow_id: entity.workflow_id, gate: entity.gate, round: entity.round, target_commit: entity.target_commit,
          base_commit: entity.base_commit, review_commit: entity.review_commit, review_path: entity.review_path, verdict: entity.verdict,
          reviewer_configuration: reviewer_configuration(entity.reviewer_configuration), dispatch_state: entity.dispatch_state, created_at: entity.created_at
        )
      end

      sig { params(stored: Workflows::Dto::RoleConfig).returns(Workflows::Dto::RoleConfig) }
      private def reviewer_configuration(stored)
        rebuilt = strictly do
          Workflows::Dto::RoleConfig.new(cli: stored.cli, provider: stored.provider, model: stored.model, family: stored.family, launch_args: stored.launch_args)
        end
        raise Errors::MalformedRecord, MALFORMED unless rebuilt.serialize == stored.serialize

        rebuilt
      end

      # from_hash raises RuntimeError for missing or unknown props and KeyError
      # for unknown enum values; constructors raise TypeError for wrong types.
      sig { type_parameters(:R).params(blk: T.proc.returns(T.type_parameter(:R))).returns(T.type_parameter(:R)) }
      private def strictly(&blk)
        yield
      rescue RuntimeError, KeyError, TypeError
        raise Errors::MalformedRecord, MALFORMED
      end
    end
  end
end
