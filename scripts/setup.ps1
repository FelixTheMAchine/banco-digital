$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Instale Docker Desktop e habilite o backend WSL 2.'
}
docker compose version
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose indisponível.' }

function New-LocalSecret([int] $Bytes) {
  $buffer = New-Object byte[] $Bytes
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
  return ([BitConverter]::ToString($buffer)).Replace('-', '').ToLowerInvariant()
}

if (-not (Test-Path '.env')) {
  $contents = [IO.File]::ReadAllText((Join-Path $PWD '.env.example'))
  $contents = $contents.Replace('change-me-local-db', (New-LocalSecret 24))
  $contents = $contents.Replace('change-me-local-secret-generate-before-running', (New-LocalSecret 64))
  [IO.File]::WriteAllText((Join-Path $PWD '.env'), $contents, (New-Object Text.UTF8Encoding $false))
  Write-Host 'Criado .env com segredos aleatórios exclusivos para desenvolvimento.'
}

docker compose config --quiet
if ($LASTEXITCODE -ne 0) { throw 'Configuração Compose inválida.' }
docker compose build
if ($LASTEXITCODE -ne 0) { throw 'Build interrompido.' }
docker compose up --detach --wait
if ($LASTEXITCODE -ne 0) { throw 'Inicialização interrompida. Consulte docker compose logs api.' }
Write-Host 'Ambiente local iniciado. Web: http://localhost:3000; saúde da API: http://localhost:3001/api/v1/health (ou portas do .env).'
