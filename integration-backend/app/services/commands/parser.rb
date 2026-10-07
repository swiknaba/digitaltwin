# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    # Chat command grammar. Each pattern is anchored to the whole body or its
    # start, so at most one Commander command and one Agent command can match.
    # Commander commands take precedence when both handles are equal.
    class Parser
      extend T::Sig

      sig { params(body: String, commander_handle: String, agent_handle: String).returns(T.nilable(Dto::Command)) }
      def call(body:, commander_handle:, agent_handle:)
        commander = Regexp.escape(commander_handle)
        commander_command(body, commander) || agent_command(body, Regexp.escape(agent_handle))
      end

      sig { params(body: String, commander: String).returns(T.nilable(Dto::Command)) }
      private def commander_command(body, commander)
        match = body.match(/\A@#{commander} recover-start ([0-9a-f-]+) ([a-z0-9]{26})\z/)
        return Dto::RecoverStart.new(request_id: capture(match, 1), thread_id: capture(match, 2)) if match

        match = body.match(/\A@#{commander} recover-session ([0-9a-f-]+) ([a-zA-Z0-9_.:-]+)\z/)
        return Dto::RecoverSession.new(operation_id: capture(match, 1), pane_id: capture(match, 2)) if match

        match = body.match(/\A@#{commander} recover-followup (followup_[A-Za-z0-9]+) (delivered|discard)\z/)
        return Dto::RecoverFollowup.new(followup_id: capture(match, 1), outcome: Dto::FollowupOutcome.deserialize(capture(match, 2))) if match

        match = body.match(/\A@#{commander} recover-commander ([0-9a-f-]+)\z/)
        return Dto::RecoverCommander.new(request_id: capture(match, 1)) if match

        match = body.match(/\A@#{commander} approve ([a-zA-Z0-9_-]+) (spec|plan) ([0-9a-f]{40})\z/)
        return Dto::Approve.new(workflow_id: capture(match, 1), gate: Dto::ApprovalGate.deserialize(capture(match, 2)), commit: capture(match, 3)) if match

        match = body.match(/\A@#{commander} route ([a-zA-Z0-9_-]+)\n(.+)/m)
        return Dto::Route.new(workflow_id: capture(match, 1), text: capture(match, 2)) if match

        Dto::MalformedDirective.new if body.match?(/\A@#{commander} (approve|route)\b/)
      end

      sig { params(body: String, agent: String).returns(T.nilable(Dto::AgentCommand)) }
      private def agent_command(body, agent)
        match = body.match(/\A@#{agent}(\s+)(start|approve|pause|resume|finish|cancel)\b/)
        return nil unless match

        Dto::AgentCommand.new(action: Dto::AgentAction.deserialize(capture(match, 2)), single_space_separator: capture(match, 1) == " ")
      end

      sig { params(match: MatchData, index: Integer).returns(String) }
      private def capture(match, index)
        value = match[index]
        raise ArgumentError, "Invalid chat command" unless value

        value
      end
    end
  end
end
