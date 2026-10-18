# typed: strict
# frozen_string_literal: true

module Controllers
  class FutureTasksController < Kirei::Controller
    extend T::Sig

    Response = T.type_alias { [Integer, T::Hash[String, String], T.any(Proc, T::Array[String])] }

    sig { returns(Response) }
    def create
      render_json(tool.create(capability: token, idempotency_key: string("idempotency_key"), text: string("text"), due_at: Time.iso8601(string("due_at")), timezone: string("timezone"), local_time: string("local_time"), references: strings("references")))
    rescue ArgumentError, KeyError => error
      render_json({ error: error.message }, status: 400)
    end

    sig { returns(Response) }
    def list
      render_json(tool.list(capability: token, cursor: optional_string("cursor"), limit: integer("limit", default: 50)))
    rescue ArgumentError, KeyError => error
      render_json({ error: error.message }, status: 400)
    end

    sig { returns(Response) }
    def show
      task = tool.find(capability: token, id: string("id"))
      return render_json({ error: "Future task not found" }, status: 404) unless task

      render_json(task)
    rescue ArgumentError, KeyError => error
      render_json({ error: error.message }, status: 400)
    end

    sig { returns(Response) }
    def update
      render_json(tool.update(capability: token, id: string("id"), expected_version: integer("expected_version"), text: optional_string("text"), due_at: optional_time("due_at"), timezone: optional_string("timezone"), local_time: optional_string("local_time")))
    rescue ArgumentError, KeyError => error
      render_json({ error: error.message }, status: 400)
    end

    sig { returns(Response) }
    def cancel
      render_json(tool.cancel(capability: token, id: string("id"), expected_version: integer("expected_version")))
    rescue ArgumentError, KeyError => error
      render_json({ error: error.message }, status: 400)
    end

    sig { returns(Response) }
    def disposition
      render_json(
        tool.record_disposition(
          capability: token, id: string("id"), expected_version: integer("expected_version"), disposition_key: string("disposition_key"), outcome: string("outcome"),
          due_at: optional_time("due_at"), timezone: optional_string("timezone"), local_time: optional_string("local_time")
        )
      )
    rescue ArgumentError, KeyError => error
      render_json({ error: error.message }, status: 400)
    end

    sig { returns(Response) }
    def resolution
      render_json(tool.resolve_uncertain(capability: token, id: string("id"), expected_version: integer("expected_version"), resolution_key: string("resolution_key"), outcome: string("outcome"), reason: optional_string("reason")))
    rescue ArgumentError, KeyError => error
      render_json({ error: error.message }, status: 400)
    end

    sig { returns(Adapters::FutureTasks::OpencodeTool) }
    private def tool = Services::Composition.instance.opencode_future_tasks

    sig { returns(String) }
    private def token
      authorization = String(request.env.fetch("HTTP_AUTHORIZATION", ""))
      raise ArgumentError, "Bearer capability is required" unless authorization.start_with?("Bearer ")

      authorization.delete_prefix("Bearer ")
    end

    sig { params(name: String).returns(String) }
    private def string(name)
      value = params.fetch(name)
      raise ArgumentError, "#{name} is required" unless value.is_a?(String)

      value
    end

    sig { params(name: String).returns(T.nilable(String)) }
    private def optional_string(name)
      value = params[name]
      raise ArgumentError, "#{name} is invalid" unless value.nil? || value.is_a?(String)

      value
    end

    sig { params(name: String, default: T.nilable(Integer)).returns(Integer) }
    private def integer(name, default: nil)
      value = params.fetch(name, default)
      Integer(value)
    end

    sig { params(name: String).returns(T.nilable(Time)) }
    private def optional_time(name)
      value = optional_string(name)
      value ? Time.iso8601(value) : nil
    end

    sig { params(name: String).returns(T::Array[String]) }
    private def strings(name)
      value = params.fetch(name, [])
      raise ArgumentError, "#{name} is invalid" unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) }

      value
    end
  end
end
