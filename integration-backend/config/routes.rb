# typed: strict
# frozen_string_literal: true

module Kirei::Routing
  Router.add_health_routes!
end
Kirei::Routing::Router.add_routes([
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/callbacks/say",
                                                              controller: Adapters::Http::Callbacks, action: "say"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/callbacks/artifact-ready", controller: Adapters::Http::Callbacks, action: "artifact_ready"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/callbacks/review-ready", controller: Adapters::Http::Callbacks, action: "review_ready"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/master/tools", controller: Adapters::Http::Master, action: "tools"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/master/reply", controller: Adapters::Http::Master, action: "reply"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::GET, path: "/internal/master/manifest", controller: Adapters::Http::Master, action: "manifest")
                                  ])
