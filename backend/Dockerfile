# syntax=docker/dockerfile:1
# Imagem de desenvolvimento. Produção exige imagem e operação endurecidas.
FROM ruby:4.0.6-slim-trixie

ENV LANG=C.UTF-8 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
      build-essential libpq-dev postgresql-client-17 libyaml-dev libffi-dev pkg-config git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile* ./
# Permite verificar TLS também no ambiente cloud com CA fornecida via BuildKit.
# Em computadores locais, não é necessário fornecer o secret proxy_ca.
RUN --mount=type=secret,id=proxy_ca \
    set -eu; if [ -f /run/secrets/proxy_ca ]; then \
      cat /etc/ssl/certs/ca-certificates.crt /run/secrets/proxy_ca > /tmp/build-ca.pem; \
      SSL_CERT_FILE=/tmp/build-ca.pem bundle install; \
      rm -f /tmp/build-ca.pem; \
    else \
      bundle install; \
    fi

RUN groupadd --gid 1000 app && useradd --uid 1000 --gid app --create-home app \
    && chown app:app /app
COPY --chown=app:app . .
USER app
EXPOSE 3001
CMD ["bundle", "exec", "rails", "server", "--binding", "0.0.0.0", "--port", "3001"]
