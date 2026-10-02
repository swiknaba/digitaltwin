# typed: strict
# frozen_string_literal: true

module Services
  module Master
    # The request-bound Master tools. Every call proves the request capability
    # first and acts only on what the request's human may access. A model may
    # propose a workflow from real conversation evidence; an unbound selection
    # still needs a human clarification command.
    class Tools
      extend T::Sig

      Code = Dto::ErrorCode
      Name = Dto::ToolName
      Field = Dto::ToolField
      Arguments = Dto::ToolArguments
      Request = Domains::Commander::Dto::MasterRequestView
      Outcome = T.type_alias { Kirei::Services::Result[Dto::ToolResponse] }
      CONTROLS = T.let(%w[pause resume finish cancel].freeze, T::Array[String])
      CONTEXT_SECONDS = 1800
      CONTEXT_LIMIT = 10
      # The source check calls chat REST. Its expected and transport failures
      # hide the item instead of failing the whole listing.
      VISIBILITY_FAILURES = T.let(
        [ArgumentError, Adapters::Mattermost::Errors::RequestFailed, IOError, SystemCallError, SocketError, Async::TimeoutError].freeze,
        T::Array[T.class_of(StandardError)]
      )

      sig do
        params(source: Domains::Messaging::VerifyHumanSource, authorize: AuthorizeRequest, request_start: Workflows::RequestStart, route: RouteFollowup,
               directory: Domains::Projects::Directory, catalog: Domains::Workflows::Catalog, inbox: Domains::Messaging::Inbox, jobs: Platform::Jobs::Store).void
      end
      def initialize(source:, authorize:, request_start:, route:, directory: Domains::Projects::Directory.new, catalog: Domains::Workflows::Catalog.new,
                     inbox: Domains::Messaging::Inbox.new, jobs: Platform::Jobs::Store.new)
        @source = source
        @authorize = authorize
        @request_start = request_start
        @route = route
        @directory = directory
        @catalog = catalog
        @inbox = inbox
        @jobs = jobs
      end

      sig { params(name: Name, arguments: Arguments, token: String).returns(Outcome) }
      def call(name:, arguments:, token:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          fields = name.fields
          next failure(Code::UnexpectedFields, "Unexpected tool fields") unless arguments.fields.sort == (fields.map(&:serialize) + ["request_id"]).sort
          next failure(Code::InvalidArguments, "Invalid tool arguments") unless fields.all? { |field| present?(arguments, field) }

          request_id = arguments.request_id
          next failure(Code::InvalidArguments, "Invalid request_id") unless request_id

          authorized = @authorize.call(id: request_id, token: token, states: [Domains::Commander::Dto::MasterRequestState::Active])
          next Kirei::Services::Result.new(errors: authorized.errors) if authorized.failed?
          next failure(Code::InvalidArguments, "Invalid evidence IDs") if arguments.fields.include?(Field::EvidenceInboxIds.serialize) && !evidence_ids(arguments)

          respond(name, arguments, authorized.result)
        end
      end

      sig { params(name: Name, arguments: Arguments, request: Request).returns(Outcome) }
      private def respond(name, arguments, request)
        case name
        when Name::ListProjects
          success(Dto::ProjectList.new(projects: @directory.all.select { |project| visible?(request, project.channel_id) }))
        when Name::ListWorkflows
          success(Dto::WorkflowList.new(workflows: @catalog.active.select { |workflow| visible?(request, workflow.channel_id) }))
        when Name::ReadContext
          success(Dto::ContextList.new(entries: @inbox.recent(since: Time.now - CONTEXT_SECONDS, limit: CONTEXT_LIMIT).filter_map { |record| context(request, record) }))
        when Name::StartWorkflow
          start(arguments, request)
        when Name::SendPrompt
          send_prompt(arguments, request)
        when Name::WorkflowControl
          control(arguments, request)
        else
          T.absurd(name)
        end
      end

      sig { params(arguments: Arguments, request: Request).returns(Outcome) }
      private def start(arguments, request)
        started = @request_start.call(inbox_id: request.inbox_id, project_id: T.must(arguments.project_id), title: T.must(arguments.title))
        return Kirei::Services::Result.new(errors: started.errors) if started.failed?

        success(Dto::StartReceipt.new(request_id: started.result))
      end

      sig { params(arguments: Arguments, request: Request).returns(Outcome) }
      private def send_prompt(arguments, request)
        interpretation = Domains::Commander::Dto::RoutingInterpretation.new(workflow_id: T.must(arguments.workflow_id), evidence_inbox_ids: T.must(evidence_ids(arguments)))
        routed = @route.call(inbox_id: request.inbox_id, interpretation: interpretation)
        return Kirei::Services::Result.new(errors: routed.errors) if routed.failed?

        success(routed.result)
      end

      sig { params(arguments: Arguments, request: Request).returns(Outcome) }
      private def control(arguments, request)
        action = T.must(arguments.action)
        return failure(Code::UnsupportedControl, "Unsupported control") unless CONTROLS.include?(action)

        w = @catalog.find(id: T.must(arguments.workflow_id))
        return failure(Code::MissingWorkflow, "Missing workflow") unless w

        verified = @source.call(inbox_id: request.inbox_id, destination: w.channel_id)
        return Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

        expected_version = T.must(arguments.expected_version)
        return failure(Code::VersionChanged, "Workflow version changed") unless w.version == expected_version

        payload = Domains::Commander::Dto::MasterControlJob.new(inbox_id: request.inbox_id, workflow_id: w.id, action: action, expected_version: expected_version)
        @jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::MasterControl, payload: payload, dispatch_key: "master:control:#{request.id}:#{w.id}:#{action}:#{w.version}")
        success(Dto::ControlReceipt.new)
      end

      # Whether the request's human may see the channel.
      sig { params(request: Request, channel_id: String).returns(T::Boolean) }
      private def visible?(request, channel_id)
        @source.call(inbox_id: request.inbox_id, destination: channel_id).success?
      rescue *VISIBILITY_FAILURES
        false
      end

      # A recent message the request's human may see; nil when either source
      # check fails.
      sig { params(request: Request, record: Domains::Messaging::Dto::InboxRecord).returns(T.nilable(Dto::ContextEntry)) }
      private def context(request, record)
        return nil if @source.call(inbox_id: request.inbox_id, destination: record.channel_id).failed?

        verified = @source.call(inbox_id: record.id)
        return nil if verified.failed?

        d = verified.result
        Dto::ContextEntry.new(inbox_id: record.id, channel_id: d.channel_id, thread_id: d.thread_id, text: d.body)
      rescue ArgumentError
        nil
      end

      # One to ten non-empty evidence ids, or nil.
      sig { params(arguments: Arguments).returns(T.nilable(T::Array[String])) }
      private def evidence_ids(arguments)
        value = arguments.evidence_inbox_ids
        return nil unless value

        ids = value.grep(String).reject(&:empty?)
        ids if ids.size == value.size && ids.size.between?(1, 10)
      end

      sig { params(arguments: Arguments, field: Field).returns(T::Boolean) }
      private def present?(arguments, field)
        value = case field
                when Field::ProjectId then arguments.project_id
                when Field::Title then arguments.title
                when Field::WorkflowId then arguments.workflow_id
                when Field::EvidenceInboxIds then arguments.evidence_inbox_ids
                when Field::Action then arguments.action
                when Field::ExpectedVersion then arguments.expected_version
                else T.absurd(field)
                end
        !value.nil?
      end

      sig { params(response: Dto::ToolResponse).returns(Outcome) }
      private def success(response) = Kirei::Services::Result.new(result: response)

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
