# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    # Chat command grammar. Each pattern is anchored to the whole body or its
    # start, so at most one agent command and one Worker command can match.
    # Agent commands take precedence when both handles are equal.
    class Parser
      extend T::Sig

      sig { params(body: String, agent_handle: String, worker_handle: String).returns(T.nilable(Dto::Command)) }
      def call(body:, agent_handle:, worker_handle:)
        agent = Regexp.escape(agent_handle)
        agent_command(body, agent) || worker_command(body, Regexp.escape(worker_handle))
      end

      private

      sig { params(body: String, agent: String).returns(T.nilable(Dto::Command)) }
      def agent_command(body, agent)
        match = body.match(/\A@#{agent} recover-start ([0-9a-f-]+) ([a-z0-9]{26})\z/)
        return Dto::RecoverStart.new(request_id: capture(match, 1), thread_id: capture(match, 2)) if match

        match = body.match(/\A@#{agent} recover-session ([0-9a-f-]+) ([a-zA-Z0-9_.:-]+)\z/)
        return Dto::RecoverSession.new(operation_id: capture(match, 1), pane_id: capture(match, 2)) if match

        match = body.match(/\A@#{agent} recover-followup ([0-9]+) (delivered|discard)\z/)
        return Dto::RecoverFollowup.new(followup_id: capture(match, 1).to_i, outcome: Dto::FollowupOutcome.deserialize(capture(match, 2))) if match

        match = body.match(/\A@#{agent} recover-master ([0-9a-f-]+)\z/)
        return Dto::RecoverMaster.new(request_id: capture(match, 1)) if match

        match = body.match(/\A@#{agent} approve ([a-zA-Z0-9-]+) (spec|plan) ([0-9a-f]{40})\z/)
        return Dto::Approve.new(workflow_id: capture(match, 1), gate: Dto::ApprovalGate.deserialize(capture(match, 2)), commit: capture(match, 3)) if match

        match = body.match(/\A@#{agent} route ([a-zA-Z0-9-]+)\n(.+)/m)
        return Dto::Route.new(workflow_id: capture(match, 1), text: capture(match, 2)) if match

        Dto::MalformedDirective.new if body.match?(/\A@#{agent} (approve|route)\b/)
      end

      sig { params(body: String, worker: String).returns(T.nilable(Dto::WorkerCommand)) }
      def worker_command(body, worker)
        match = body.match(/\A@#{worker}(\s+)(start|approve|pause|resume|finish|cancel)\b/)
        return nil unless match

        Dto::WorkerCommand.new(action: Dto::WorkerAction.deserialize(capture(match, 2)), single_space_separator: capture(match, 1) == " ")
      end

      sig { params(match: MatchData, index: Integer).returns(String) }
      def capture(match, index)
        value = match[index]
        raise ArgumentError, "Invalid chat command" unless value

        value
      end
    end
  end
end
