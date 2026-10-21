#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v docker >/dev/null || { echo 'Instale o Docker Engine com Compose ou Docker Desktop.' >&2; exit 1; }
docker compose version >/dev/null
if [[ ! -f .env ]]; then
  command -v openssl >/dev/null || { echo 'Instale openssl para gerar os segredos locais.' >&2; exit 1; }
  local_db_password="$(openssl rand -hex 24)"
  local_rails_secret="$(openssl rand -hex 64)"
  umask 077
  sed -e "s/change-me-local-db/${local_db_password}/g" \
      -e "s/change-me-local-secret-generate-before-running/${local_rails_secret}/g" \
      .env.example > .env
  echo 'Criado .env com segredos aleatórios exclusivos para desenvolvimento.'
fi

docker compose config --quiet
docker compose build
docker compose up --detach --wait
echo 'Ambiente local iniciado. Web: http://localhost:3000; saúde da API: http://localhost:3001/api/v1/health (ou portas do .env).'
