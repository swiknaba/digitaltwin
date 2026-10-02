# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    # Per-channel chat history checkpoints and quarantine receipts for
    # rejected history posts.
    class Checkpoints
      extend T::Sig

      sig { params(channel_id: String).returns(Integer) }
      def revision(channel_id:)
        checkpoint = Entities::ChatCheckpoint.find_by(channel_id: channel_id)
        return 0 unless checkpoint
        raise IOError, "Malformed chat checkpoint" if checkpoint.post_revision.negative?

        checkpoint.post_revision
      end

      # The upsert keeps the greater revision, so a checkpoint never moves back.
      sig { params(channel_id: String, revision: Integer).void }
      def advance(channel_id:, revision:)
        table = Entities::ChatCheckpoint.table_name.to_sym
        Entities::ChatCheckpoint.query.insert_conflict(
          target: :channel_id,
          update: { post_revision: Sequel.function(:greatest, Sequel[table][:post_revision], revision) }
        ).insert(channel_id: channel_id, post_revision: revision)
      end

      # `digest` identifies the rejected post as received; the event key keeps
      # the pre-refactor "history-rejected:<digest>" format.
      sig { params(channel_id: String, post_id: T.nilable(String), digest: String, reason: String).void }
      def quarantine(channel_id:, post_id:, digest:, reason:)
        Platform::Audit::Log.new.record_once(event_key: "history-rejected:#{digest}", action: "history_rejected", channel_id: channel_id,
                                             post_id: post_id, details: Dto::HistoryRejectedAudit.new(reason: reason))
      end
    end
  end
end
