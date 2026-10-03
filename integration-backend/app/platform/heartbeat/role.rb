# typed: strict
# frozen_string_literal: true

module Platform
  class Heartbeat
    # Process roles without an HTTP port; `bin/health <role>` reads their heartbeat file.
    class Role < T::Enum
      enums do
        Worker = new("worker")
        ChatListener = new("chat-listener")
      end
    end
  end
end
