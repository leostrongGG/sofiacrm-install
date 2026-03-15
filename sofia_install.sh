#!/usr/bin/env bash
# ==============================================================
#  SofiaCRM — Instalador Automático v1.1
#  Repositório: https://github.com/leostrongGG/sofiacrm-install
# ==============================================================
set -euo pipefail

# ── Auto-elevação para root ────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INSTALL_DIR"

# Variáveis globais — inicializadas vazias para o set -u não reclamar
CRM_DOMAIN="${CRM_DOMAIN:-}"
ACME_EMAIL="${ACME_EMAIL:-}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
JWT_SECRET="${JWT_SECRET:-}"
INTERNAL_TOKEN="${INTERNAL_TOKEN:-}"
META_CLOUD_SERVICE_TOKEN="${META_CLOUD_SERVICE_TOKEN:-}"
STORAGE_TYPE="${STORAGE_TYPE:-local}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
AWS_REGION="${AWS_REGION:-}"
AWS_S3_BUCKET_NAME="${AWS_S3_BUCKET_NAME:-}"
AWS_S3_ENDPOINT="${AWS_S3_ENDPOINT:-}"
AWS_S3_FORCE_PATH_STYLE="${AWS_S3_FORCE_PATH_STYLE:-false}"

# ── Banner ─────────────────────────────────────────────────────────────────────
print_banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════════════╗"
  echo "  ║           Sofia CRM — Instalador Automático           ║"
  echo "  ║                      v1.1                             ║"
  echo "  ╚═══════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo ""
}

# ── Menu principal ─────────────────────────────────────────────────────────────
main_menu() {
  echo -e "${BLUE}${BOLD}  O que deseja fazer?${NC}"
  echo ""
  echo "    1) Instalar   — nova instalação do SofiaCRM"
  echo "    2) Editar     — alterar configurações e reiniciar"
  echo "    3) Atualizar  — atualizar imagens para a versão mais recente"
  echo ""
  while true; do
    read -rp "  Escolha [1/2/3]: " MENU_CHOICE
    [[ "$MENU_CHOICE" == "1" || "$MENU_CHOICE" == "2" || "$MENU_CHOICE" == "3" ]] && break
    echo -e "${RED}  ✗ Digite 1, 2 ou 3${NC}"
  done
  echo ""
}

# ── Checks ─────────────────────────────────────────────────────────────────────
check_arch() {
  if [ "$(uname -m)" != "x86_64" ]; then
    echo -e "${RED}✗ Arquitetura não suportada: $(uname -m)${NC}"
    echo -e "  O SofiaCRM requer AMD64 (x86_64)."
    exit 1
  fi
  echo -e "${GREEN}✓ Arquitetura AMD64${NC}"
}

# ── Docker ─────────────────────────────────────────────────────────────────────
install_docker() {
  if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version | grep -oP '\d+\.\d+' | head -1)
    echo -e "${GREEN}✓ Docker ${DOCKER_VER} já instalado${NC}"
    return
  fi
  echo -e "${YELLOW}→ Docker não encontrado. Instalando...${NC}"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  echo -e "${GREEN}✓ Docker instalado${NC}"
}

# ── Coleta de informações ──────────────────────────────────────────────────────
# Exibe o valor atual entre colchetes quando existir — Enter mantém o valor
collect_info() {
  echo -e "${BLUE}${BOLD}─── Configuração ──────────────────────────────────────────────${NC}"
  echo ""

  local domain_hint="${CRM_DOMAIN:+ [${CRM_DOMAIN}]}"
  local email_hint="${ACME_EMAIL:+ [${ACME_EMAIL}]}"

  while true; do
    read -rp "  Domínio do CRM${domain_hint} (ex: crm.seudominio.com): " input
    CRM_DOMAIN="${input:-${CRM_DOMAIN}}"
    [[ -n "$CRM_DOMAIN" ]] && break
    echo -e "${RED}  ✗ Domínio não pode ser vazio${NC}"
  done

  while true; do
    read -rp "  E-mail para certificado SSL (Let's Encrypt)${email_hint}: " input
    ACME_EMAIL="${input:-${ACME_EMAIL}}"
    [[ "$ACME_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
    echo -e "${RED}  ✗ E-mail inválido${NC}"
  done

  echo ""
  echo -e "  ${BOLD}Storage de mídia:${NC}"
  echo "    1) Local  — arquivos salvos no disco da VPS (padrão, mais simples)"
  echo "    2) S3     — Backblaze B2, AWS S3, Cloudflare R2, MinIO..."
  echo ""

  local storage_default="1"
  [[ "${STORAGE_TYPE}" == "s3" ]] && storage_default="2"

  while true; do
    read -rp "  Escolha [1/2] (atual: ${storage_default}): " STORAGE_CHOICE
    STORAGE_CHOICE="${STORAGE_CHOICE:-${storage_default}}"
    [[ "$STORAGE_CHOICE" == "1" || "$STORAGE_CHOICE" == "2" ]] && break
    echo -e "${RED}  ✗ Digite 1 ou 2${NC}"
  done

  if [ "$STORAGE_CHOICE" == "2" ]; then
    STORAGE_TYPE="s3"
    echo ""
    echo -e "  ${BOLD}Dados do S3:${NC}"

    local key_hint="${AWS_ACCESS_KEY_ID:+ [${AWS_ACCESS_KEY_ID}]}"
    local region_hint="${AWS_REGION:+ [${AWS_REGION}]}"
    local bucket_hint="${AWS_S3_BUCKET_NAME:+ [${AWS_S3_BUCKET_NAME}]}"
    local endpoint_hint="${AWS_S3_ENDPOINT:+ [${AWS_S3_ENDPOINT}]}"
    local secret_hint="${AWS_SECRET_ACCESS_KEY:+ [configurada — Enter para manter]}"

    read -rp  "    Access Key ID${key_hint}: " input
    AWS_ACCESS_KEY_ID="${input:-${AWS_ACCESS_KEY_ID}}"

    read -rsp "    Secret Access Key${secret_hint}: " input
    AWS_SECRET_ACCESS_KEY="${input:-${AWS_SECRET_ACCESS_KEY}}"
    echo ""

    read -rp  "    Region (ex: us-east-005)${region_hint}: " input
    AWS_REGION="${input:-${AWS_REGION}}"

    read -rp  "    Nome do Bucket${bucket_hint}: " input
    AWS_S3_BUCKET_NAME="${input:-${AWS_S3_BUCKET_NAME}}"

    read -rp  "    Endpoint S3 (ex: https://s3.us-east-005.backblazeb2.com)${endpoint_hint}: " input
    AWS_S3_ENDPOINT="${input:-${AWS_S3_ENDPOINT}}"

    AWS_S3_FORCE_PATH_STYLE="true"
  else
    STORAGE_TYPE="local"
    AWS_ACCESS_KEY_ID=""
    AWS_SECRET_ACCESS_KEY=""
    AWS_REGION=""
    AWS_S3_BUCKET_NAME=""
    AWS_S3_ENDPOINT=""
    AWS_S3_FORCE_PATH_STYLE="false"
  fi

  echo ""
}

# ── Geração de tokens ─────────────────────────────────────────────────────────
generate_secrets() {
  echo -e "${YELLOW}→ Gerando senhas e tokens de segurança...${NC}"
  POSTGRES_PASSWORD=$(openssl rand -hex 32)
  REDIS_PASSWORD=$(openssl rand -hex 32)
  JWT_SECRET=$(openssl rand -hex 32)
  INTERNAL_TOKEN=$(openssl rand -hex 32)
  META_CLOUD_SERVICE_TOKEN=$(openssl rand -hex 32)
  echo -e "${GREEN}✓ Tokens gerados automaticamente${NC}"
}

# ── Criar .env ────────────────────────────────────────────────────────────────
create_env() {
  echo -e "${YELLOW}→ Gravando .env...${NC}"

  cat > "$INSTALL_DIR/.env" <<EOF
# =============================================================
# SofiaCRM — Configurações de ambiente
# Gerado automaticamente em $(date '+%Y-%m-%d %H:%M:%S')
# NUNCA commitar ou compartilhar este arquivo!
# =============================================================

# Domínio e e-mail (usado pelo Traefik / Let's Encrypt)
CRM_DOMAIN=${CRM_DOMAIN}
ACME_EMAIL=${ACME_EMAIL}

# Banco de dados PostgreSQL
# Usuário padrão da imagem Docker: postgres (não é configurável)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Redis
# Redis não usa nome de usuário — somente senha
REDIS_PASSWORD=${REDIS_PASSWORD}

# Segurança da aplicação
# JWT_SECRET: assina os tokens de sessão dos usuários do CRM
# INTERNAL_TOKEN: autentica chamadas internas crm_api <-> whats-service
# META_CLOUD_SERVICE_TOKEN: token INTERNO entre crm_api <-> meta-cloud-service
#   (NÃO é da Meta/Facebook — é gerado por você para comunicação entre containers)
JWT_SECRET=${JWT_SECRET}
INTERNAL_TOKEN=${INTERNAL_TOKEN}
META_CLOUD_SERVICE_TOKEN=${META_CLOUD_SERVICE_TOKEN}

# Storage de mídia (local ou s3)
STORAGE_TYPE=${STORAGE_TYPE}
EOF

  if [ "$STORAGE_TYPE" == "s3" ]; then
    cat >> "$INSTALL_DIR/.env" <<EOF
# S3 — Backblaze B2 / AWS S3 / Cloudflare R2 / MinIO
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION}
AWS_S3_BUCKET_NAME=${AWS_S3_BUCKET_NAME}
AWS_S3_ENDPOINT=${AWS_S3_ENDPOINT}
AWS_S3_FORCE_PATH_STYLE=${AWS_S3_FORCE_PATH_STYLE}
EOF
  fi

  echo -e "${GREEN}✓ .env gravado${NC}"
}

# ── Traefik ───────────────────────────────────────────────────────────────────
setup_traefik() {
  echo -e "${YELLOW}→ Configurando Traefik...${NC}"
  mkdir -p "$INSTALL_DIR/traefik"

  if [ ! -f "$INSTALL_DIR/traefik/acme.json" ]; then
    : > "$INSTALL_DIR/traefik/acme.json"
  fi
  chmod 600 "$INSTALL_DIR/traefik/acme.json"

  cat > "$INSTALL_DIR/traefik/traefik.yml" <<EOF
api:
  dashboard: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entrypoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"

certificatesResolvers:
  letsencryptresolver:
    acme:
      httpChallenge:
        entryPoint: web
      email: ${ACME_EMAIL}
      storage: /acme/acme.json

providers:
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true

log:
  level: INFO

accessLog: {}
EOF

  cat > "$INSTALL_DIR/traefik/dynamic.yml" <<EOF
http:
  routers:
    crm_api:
      rule: "Host(\`${CRM_DOMAIN}\`)"
      entryPoints:
        - websecure
      service: crm_api
      tls:
        certResolver: letsencryptresolver
      priority: 1

    meta_webhook:
      rule: "Host(\`${CRM_DOMAIN}\`) && PathPrefix(\`/api/webhooks/meta/whatsapp\`)"
      entryPoints:
        - websecure
      service: meta_cloud
      tls:
        certResolver: letsencryptresolver
      priority: 20

    meta_cloud_api:
      rule: "Host(\`${CRM_DOMAIN}\`) && PathPrefix(\`/api/meta-cloud\`)"
      entryPoints:
        - websecure
      service: meta_cloud
      tls:
        certResolver: letsencryptresolver
      priority: 20

  services:
    crm_api:
      loadBalancer:
        servers:
          - url: "http://crm_api:3000"

    meta_cloud:
      loadBalancer:
        servers:
          - url: "http://crm_meta_cloud:8090"
EOF

  echo -e "${GREEN}✓ Traefik configurado${NC}"
}

# ── Deploy ────────────────────────────────────────────────────────────────────
start_services() {
  echo ""
  echo -e "${BLUE}${BOLD}─── Iniciando serviços ────────────────────────────────────────${NC}"
  echo ""
  echo -e "${YELLOW}→ Subindo todos os containers (Traefik → PostgreSQL → Redis → CRM)...${NC}"
  echo -e "   (o banco 'crm' é criado automaticamente pelo PostgreSQL)"
  echo ""
  docker compose up -d
  echo -e "${GREEN}✓ Todos os serviços iniciados${NC}"
}

# ── Aguarda CRM ───────────────────────────────────────────────────────────────
wait_crm_healthy() {
  echo ""
  echo -e "${YELLOW}→ Aguardando CRM inicializar (pode levar até 60s)...${NC}"
  for i in $(seq 1 40); do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' crm_api 2>/dev/null || echo "wait")
    if [[ "$STATUS" == "healthy" ]]; then
      echo -e "${GREEN}✓ CRM pronto!${NC}"
      return
    fi
    sleep 2
    printf "  tentativa %d/40...\r" "$i"
  done
  echo -e "${YELLOW}⚠ CRM ainda inicializando. Verifique com: docker logs crm_api --tail 20${NC}"
}

# ── Resumo final ──────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  ✓  SofiaCRM pronto!${NC}"
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${BOLD}➜ Primeiro acesso — criar conta de administrador:${NC}"
  echo -e "     ${CYAN}https://${CRM_DOMAIN}/pages/install.html${NC}"
  echo ""
  echo -e "  ${BOLD}➜ Login após criar a conta:${NC}"
  echo -e "     ${CYAN}https://${CRM_DOMAIN}${NC}"
  echo ""
  echo -e "  ${BOLD}Containers em execução:${NC}"
  docker ps --format "    {{.Names}}: {{.Status}}"
  echo ""
  echo -e "  ${YELLOW}⚠  Suas senhas estão salvas em: ${INSTALL_DIR}/.env${NC}"
  echo -e "  ${RED}   Nunca compartilhe ou commite este arquivo!${NC}"
  echo ""
}

# ── Ação 1: Instalar ──────────────────────────────────────────────────────────
action_instalar() {
  check_arch
  install_docker
  collect_info
  generate_secrets
  create_env
  setup_traefik
  start_services
  wait_crm_healthy
  print_summary
}

# ── Ação 2: Editar ────────────────────────────────────────────────────────────
action_editar() {
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo -e "${RED}✗ Arquivo .env não encontrado. Use a opção 1 para instalar primeiro.${NC}"
    exit 1
  fi

  echo -e "${YELLOW}→ Carregando configuração atual...${NC}"
  set -a
  # shellcheck disable=SC1091
  source "$INSTALL_DIR/.env"
  set +a
  echo -e "${GREEN}✓ Configurações carregadas${NC}"
  echo ""

  collect_info

  echo -e "  ${BOLD}Senhas e tokens:${NC}"
  read -rp "  Deseja regenerar todas as senhas e tokens? [s/N]: " REGEN
  echo ""
  if [[ "${REGEN,,}" == "s" ]]; then
    generate_secrets
  else
    echo -e "${GREEN}✓ Senhas e tokens mantidos${NC}"
  fi

  create_env
  setup_traefik

  echo -e "${YELLOW}→ Reiniciando serviços com as novas configurações...${NC}"
  docker compose down
  docker compose up -d
  wait_crm_healthy
  print_summary
}

# ── Ação 3: Atualizar ─────────────────────────────────────────────────────────
action_atualizar() {
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo -e "${RED}✗ Arquivo .env não encontrado. Use a opção 1 para instalar primeiro.${NC}"
    exit 1
  fi

  echo ""
  echo -e "${BLUE}${BOLD}─── Atualizando SofiaCRM ──────────────────────────────────────${NC}"
  echo ""
  echo -e "${YELLOW}→ Baixando imagens mais recentes...${NC}"
  docker compose pull
  echo -e "${YELLOW}→ Reiniciando containers...${NC}"
  docker compose down
  docker compose up -d
  wait_crm_healthy

  echo ""
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  ✓  SofiaCRM atualizado com sucesso!${NC}"
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${BOLD}Containers em execução:${NC}"
  docker ps --format "    {{.Names}}: {{.Status}}"
  echo ""
}

# ── Execução principal ────────────────────────────────────────────────────────
print_banner
main_menu

case "$MENU_CHOICE" in
  1) action_instalar ;;
  2) action_editar ;;
  3) action_atualizar ;;
esac
