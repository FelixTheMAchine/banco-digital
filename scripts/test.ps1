param([Parameter(ValueFromRemainingArguments = $true)][string[]] $TestArguments)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if (-not (Test-Path '.env')) { throw 'Execute .\scripts\setup.ps1 primeiro.' }
# Duas chamadas evitam aspas aninhadas no modo nativo legado do PowerShell 5.1.
docker compose run --rm --build test bundle exec rails db:prepare
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
docker compose run --rm test bundle exec rspec @TestArguments
exit $LASTEXITCODE
