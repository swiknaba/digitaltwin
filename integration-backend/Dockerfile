FROM ruby:4.0.7-alpine@sha256:1ca7cb33e970630d571e0da6140e0bc925faec8f1f8f51f9f2cdf5e5f5eed7c9 AS dependencies
RUN apk add --no-cache build-base=0.5-r4 libpq-dev=18.6-r0 liburing-dev=2.14-r0 git=2.54.0-r0 bash=5.3.9-r1 gcompat=1.1.0-r4
WORKDIR /app
RUN gem install bundler -v 4.0.20 --no-document
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install

# Tapioca's precompiled Ruby 4 helper requires glibc. Keep this check-only image
# separate from the Alpine runtime so production native gems remain musl-linked.
FROM ruby:4.0.7-bookworm@sha256:119a36c51c7893215202220eabfdcb561638735de4d45bacf2e8619be3de47f2 AS typecheck
WORKDIR /app
RUN gem install bundler -v 4.0.20 --no-document
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install
COPY . .
CMD ["bundle", "exec", "srb", "tc"]

FROM ruby:4.0.7-alpine@sha256:1ca7cb33e970630d571e0da6140e0bc925faec8f1f8f51f9f2cdf5e5f5eed7c9
RUN apk add --no-cache libpq=18.6-r0 liburing=2.14-r0 git=2.54.0-r0 bash=5.3.9-r1 gcompat=1.1.0-r4 && addgroup -g 10001 digitaltwin && adduser -D -u 10001 -G digitaltwin digitaltwin
WORKDIR /app
COPY --from=dependencies /usr/local/bundle /usr/local/bundle
COPY --chown=10001:10001 . .
ENV RACK_ENV=production APP_VERSION=development PORT=3000
USER 10001:10001
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=5s --start-period=15s CMD ["bin/health", "web"]
CMD ["bin/web"]
