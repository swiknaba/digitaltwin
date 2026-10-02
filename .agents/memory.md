# Repository Memory

- Integration backend dependency loading is centralized in `app.rb`: Gemfile group selection is the only production, development, and test loading boundary. Do not use `require: false` in its Gemfile or explicit `require` calls in `integration-backend/app/`.
