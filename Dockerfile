FROM ghcr.io/gitroomhq/postiz-app:latest

# Strip provider OAuth scopes that fail authorize:
# TikTok video.list / video.create, YouTube youtubepartner (CMS-only).
COPY scripts/patch-tiktok-scopes.sh /tmp/patch-tiktok-scopes.sh
RUN node /tmp/patch-tiktok-scopes.sh
