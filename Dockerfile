FROM ruby:3.3-alpine
MAINTAINER Samuel Cochran <sj26@sj26.com>

ARG VERSION=0.12.0

COPY ./mailcatcher-${VERSION}.gem /tmp/

# sqlite3 aarch64 is broken on alpine, so use ruby:
# https://github.com/sparklemotion/sqlite3-ruby/issues/372
RUN apk add --no-cache build-base sqlite-libs sqlite-dev libstdc++ && \
    ( [ "$(uname -m)" != "aarch64" ] || gem install sqlite3 --version="~> 1.3" --platform=ruby ) && \
    gem install /tmp/mailcatcher-${VERSION}.gem && \
    apk del --rdepends --purge build-base sqlite-dev

EXPOSE 1025 1080

ENTRYPOINT ["mailcatcher", "--foreground"]
CMD ["--ip", "0.0.0.0"]
