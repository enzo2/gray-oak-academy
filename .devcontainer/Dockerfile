# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.2
FROM ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION

RUN sudo apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && sudo apt-get -y install --no-install-recommends \
        postgresql-client postgresql-contrib libpq-dev \
        ffmpeg libvips-dev poppler-utils \
        libxml2-dev sqlite3 imagemagick