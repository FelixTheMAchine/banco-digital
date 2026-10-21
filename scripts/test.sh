#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -f .env ]] || { echo 'Execute bash scripts/setup.sh primeiro.' >&2; exit 1; }
docker compose run --rm --build test bash -lc \
  'bundle exec rails db:prepare && bundle exec rspec "$@"' bash "$@"
