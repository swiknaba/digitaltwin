# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    # Human follow-up instructions for a workflow's Writer session, delivered
    # in creation order. Callers hold the workflow's Platform::Lock for status
    # changes. Reads fail closed with Errors::MalformedRecord on a row that
    # does not match its typed shape, including its evidence JSONB.
    class Followups
      extend T::Sig

      Status = Dto::FollowupStatus
      MALFORMED = "Malformed durable follow-up record"
      PENDING = T.let([Status::Queued, Status::Sending, Status::Uncertain].map(&:serialize).freeze, T::Array[String])

      # Idempotent per inbox: a second create returns the first follow-up. A
      # follow-up without a session is blocked until reconciliation.
      sig do
        params(inbox_id: String, workflow_id: String, session: T.nilable(Sessions::Dto::SessionView), evidence: Dto::RoutingEvidence)
          .returns(Kirei::Services::Result[Dto::FollowupView])
      end
      def create(inbox_id:, workflow_id:, session:, evidence:)
        existing = for_inbox(inbox_id: inbox_id)
        return Kirei::Services::Result.new(result: existing) if existing

        status = session ? Status::Queued : Status::Blocked
        entity = Entities::Followup.create(inbox_id: inbox_id, workflow_id: workflow_id, session_id: session&.id, generation: session&.generation,
                                           evidence: evidence.serialize, status: status.serialize, reason: session ? nil : "Session reconciliation required")
        Kirei::Services::Result.new(result: view(entity))
      end

      sig { params(id: String).returns(T.nilable(Dto::FollowupView)) }
      def find(id:) = first(Entities::Followup.query.where(id: id))

      sig { params(inbox_id: String).returns(T.nilable(Dto::FollowupView)) }
      def for_inbox(inbox_id:) = first(Entities::Followup.query.where(inbox_id: inbox_id))

      # Sets the status, and the reason and delivery time when given. With
      # `from`, only a follow-up still in that status changes.
      sig { params(id: String, status: Status, reason: T.nilable(String), delivered_at: T.nilable(Time), from: T.nilable(Status)).void }
      def mark(id:, status:, reason: nil, delivered_at: nil, from: nil)
        changes = T.let({ status: status.serialize }, T::Hash[Symbol, T.any(String, Time)])
        changes[:reason] = reason if reason
        changes[:delivered_at] = delivered_at if delivered_at
        query = Entities::Followup.query.where(id: id)
        query = query.where(status: from.serialize) if from
        query.update(changes)
      end

      # Whether an earlier follow-up of the workflow is queued, sending or
      # uncertain. Ids are random, so order follows created_at with id as the
      # tiebreaker.
      sig { params(id: String, workflow_id: String).returns(T::Boolean) }
      def pending_before?(id:, workflow_id:)
        table = Entities::Followup.table_name.to_sym
        created_at = Entities::Followup.query.where(id: id).select(:created_at)
        earlier = Sequel.|(Sequel[table][:created_at] < created_at, Sequel.&(Sequel[table][:created_at] =~ created_at, Sequel[table][:id] < id))
        !Entities::Followup.query.where(workflow_id: workflow_id).where(earlier).where(status: PENDING).empty?
      end

      sig { params(workflow_id: String).returns(T::Array[String]) }
      def queued_ids(workflow_id:)
        Entities::Followup.query.where(workflow_id: workflow_id, status: Status::Queued.serialize).select_map(:id).grep(String)
      end

      # T::Struct.from_hash checks neither nested types nor nested unknown
      # keys, so the evidence is rebuilt through its constructors and compared
      # with its stored form.
      sig { params(query: Sequel::Dataset).returns(T.nilable(Dto::FollowupView)) }
      private def first(query)
        entity = strictly { Entities::Followup.resolve_first(query, true) }
        entity && view(entity)
      end

      sig { params(entity: Entities::Followup).returns(Dto::FollowupView) }
      private def view(entity)
        Dto::FollowupView.new(id: entity.id, inbox_id: entity.inbox_id, workflow_id: entity.workflow_id, session_id: entity.session_id,
                              generation: entity.generation, status: entity.status, reason: entity.reason, evidence: evidence(entity.evidence),
                              created_at: entity.created_at, delivered_at: entity.delivered_at)
      end

      sig { params(stored: Dto::RoutingEvidence).returns(Dto::RoutingEvidence) }
      private def evidence(stored)
        rebuilt = strictly do
          interpretation = stored.interpretation
          Dto::RoutingEvidence.new(
            selection: stored.selection, direct_thread: stored.direct_thread, recent_binding: stored.recent_binding, source_inbox_id: stored.source_inbox_id,
            interpretation: interpretation && Dto::RoutingInterpretation.new(workflow_id: interpretation.workflow_id, evidence_inbox_ids: interpretation.evidence_inbox_ids),
            attribution: attribution(stored.attribution)
          )
        end
        raise Errors::MalformedRecord, MALFORMED unless rebuilt.serialize == stored.serialize

        rebuilt
      end

      sig { params(stored: T.nilable(Dto::InstructionAttribution)).returns(T.nilable(Dto::InstructionAttribution)) }
      private def attribution(stored)
        stored && Dto::InstructionAttribution.new(effective_sender: stored.effective_sender, origin_inbox_id: stored.origin_inbox_id,
                                                  origin_user_id: stored.origin_user_id, mode: stored.mode)
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
