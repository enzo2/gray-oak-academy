# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.6
FROM ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION

RUN sudo apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && sudo apt-get -y install --no-install-recommends \
        postgresql-client postgresql-contrib libpq-dev \
        ffmpeg libvips-dev poppler-utils  \
        libxml2-dev sqlite3 imagemagick \
        libatk1.0-0 libatk-bridge2.0-0 fonts-liberation libcups2 libgcc1 libglib2.0-0 libgtk-3-0 \
        libxcomposite1 xdg-utils libxtst6 libxdamage1 \
        libclang-dev clang cargo
