# typed: strict
# frozen_string_literal: true

module Kirei::Routing
  Router.add_health_routes!
end
Kirei::Routing::Router.add_routes([
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/callbacks/say",
                                                              controller: Domains::Commander::Http::Callbacks, action: "say"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/callbacks/artifact-ready", controller: Domains::Commander::Http::Callbacks, action: "artifact_ready"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/callbacks/review-ready", controller: Domains::Commander::Http::Callbacks, action: "review_ready"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/master/tools", controller: Domains::Commander::Http::Master, action: "tools"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/master/reply", controller: Domains::Commander::Http::Master, action: "reply"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::GET, path: "/internal/master/manifest", controller: Domains::Commander::Http::Master, action: "manifest")
                                  ])
