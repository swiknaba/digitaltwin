# typed: strict
# frozen_string_literal: true

module Kirei::Routing
  Router.add_health_routes!
  Router.add_routes(
    [
      Route.new(verb: Verb::POST, path: "/v1/future-tasks", controller: ::Controllers::FutureTasksController, action: "create"),
      Route.new(verb: Verb::GET, path: "/v1/future-tasks", controller: ::Controllers::FutureTasksController, action: "list"),
      Route.new(verb: Verb::GET, path: "/v1/future-tasks/:id", controller: ::Controllers::FutureTasksController, action: "show"),
      Route.new(verb: Verb::PATCH, path: "/v1/future-tasks/:id", controller: ::Controllers::FutureTasksController, action: "update"),
      Route.new(verb: Verb::DELETE, path: "/v1/future-tasks/:id", controller: ::Controllers::FutureTasksController, action: "cancel"),
      Route.new(verb: Verb::POST, path: "/v1/future-tasks/:id/dispositions", controller: ::Controllers::FutureTasksController, action: "disposition"),
      Route.new(verb: Verb::POST, path: "/v1/future-tasks/:id/resolution", controller: ::Controllers::FutureTasksController, action: "resolution")
    ]
  )
end
