# typed: strict
# frozen_string_literal: true

module Kirei::Routing
  Router.add_health_routes!
end
Kirei::Routing::Router.add_routes([
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/callbacks/say",
                                                              controller: Controllers::Callbacks, action: "say"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/callbacks/artifact-ready", controller: Controllers::Callbacks, action: "artifact_ready"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/callbacks/review-ready", controller: Controllers::Callbacks, action: "review_ready"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/master/tools", controller: Controllers::Master, action: "tools"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::POST, path: "/internal/master/reply", controller: Controllers::Master, action: "reply"),
                                    Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::GET, path: "/internal/master/manifest", controller: Controllers::Master, action: "manifest")
                                  ])
