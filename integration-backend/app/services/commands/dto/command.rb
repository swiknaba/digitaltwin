# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      Command = T.type_alias do
        T.any(RecoverStart, RecoverSession, RecoverFollowup, RecoverCommander, Approve, Route, MalformedDirective, AgentCommand)
      end
    end
  end
end
