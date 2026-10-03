# syntax=docker/dockerfile:1
# Official compiled server stays unchanged. Final scratch copy prevents removed
# plugin archives from remaining in inherited image layers.
FROM --platform=linux/amd64 mattermost/mattermost-team-edition:11.11.1 AS official
FROM --platform=linux/amd64 busybox:1.37.0-musl AS pruned
RUN --mount=from=official,source=/,target=/upstream \
    mkdir /output && cp -a /upstream/. /output/ && \
    rm -rf /output/mattermost/prepackaged_plugins /output/mattermost/plugins /output/mattermost/client/plugins

FROM scratch
COPY --from=pruned /output/ /
USER mattermost
WORKDIR /mattermost
ENV PATH=/mattermost/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    MM_SERVICESETTINGS_ENABLELOCALMODE=true \
    MM_INSTALL_TYPE=docker \
    MM_PLUGINSETTINGS_ENABLE=false \
    MM_PLUGINSETTINGS_ENABLEUPLOADS=false \
    MM_PLUGINSETTINGS_ENABLEMARKETPLACE=false \
    MM_PLUGINSETTINGS_ENABLEREMOTEMARKETPLACE=false \
    MM_PLUGINSETTINGS_AUTOMATICPREPACKAGEDPLUGINS=false
EXPOSE 8065
VOLUME ["/mattermost/config", "/mattermost/data", "/mattermost/logs"]
HEALTHCHECK --interval=30s --timeout=10s CMD ["/mattermost/bin/mmctl", "system", "status", "--local"]
CMD ["/mattermost/bin/mattermost"]
