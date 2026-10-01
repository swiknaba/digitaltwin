# typed: strict
# frozen_string_literal: true

module Kirei::Routing
  Router.add_health_routes!
end
Kirei::Routing::Router.add_routes([
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/callbacks/say",
                                                              controller: Controllers::Callbacks, action: "say")
                                  ])
