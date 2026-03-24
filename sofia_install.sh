#!/usr/bin/env bash
# ==============================================================
#  SofiaCRM — Instalador Automático v1.3
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
CRM_EDITION="${CRM_EDITION:-free}"
LICENSE_TOKEN="${LICENSE_TOKEN:-}"
VPS_PUBLIC_IP="${VPS_PUBLIC_IP:-}"
DOCKERHUB_USER="${DOCKERHUB_USER:-}"
DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-}"
N8N_DOMAIN="${N8N_DOMAIN:-}"
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-}"

# ── Banner ─────────────────────────────────────────────────────────────────────
print_banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════════════╗"
  echo "  ║           Sofia CRM — Instalador Automático           ║"
  echo "  ║                      v1.3                             ║"
  echo "  ╚═══════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo ""
}

# ── Menu principal ─────────────────────────────────────────────────────────────
main_menu() {
  echo -e "${BLUE}${BOLD}  O que deseja fazer?${NC}"
  echo ""
  echo "    1) Instalar SofiaCRM       — nova instalação (Free ou PRO)"
  echo "    2) Upgrade para SofiaCRM Pro — fazer upgrade da edição Free para PRO"
  echo "    3) Editar Instalação        — alterar configurações e reiniciar"
  echo "    4) Atualizar SofiaCRM       — atualizar imagens para a versão mais recente"
  echo "    5) Instalar n8n             — automação de workflows (opcional)"
  echo ""
  while true; do
    read -rp "  Escolha [1/2/3/4/5]: " MENU_CHOICE
    [[ "$MENU_CHOICE" =~ ^[12345]$ ]] && break
    echo -e "${RED}  ✗ Digite 1, 2, 3, 4 ou 5${NC}"
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
    local secret_hint="${AWS_SECRET_ACCESS_KEY:+ [${AWS_SECRET_ACCESS_KEY}]}"

    read -rp  "    Access Key ID${key_hint}: " input
    AWS_ACCESS_KEY_ID="${input:-${AWS_ACCESS_KEY_ID}}"

    read -rp "    Secret Access Key${secret_hint}: " input
    AWS_SECRET_ACCESS_KEY="${input:-${AWS_SECRET_ACCESS_KEY}}"

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

# ── Coleta de informações PRO ─────────────────────────────────────────────────
collect_pro_info() {
  echo ""
  echo -e "${BLUE}${BOLD}─── Configuração PRO ──────────────────────────────────────────${NC}"
  echo ""

  local license_hint="${LICENSE_TOKEN:+ [configurado — Enter para manter]}"

  # Auto-detect IP público se ainda não configurado
  if [[ -z "$VPS_PUBLIC_IP" ]]; then
    local detected_ip
    detected_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "")
    [[ -n "$detected_ip" ]] && VPS_PUBLIC_IP="$detected_ip"
  fi
  local ip_hint="${VPS_PUBLIC_IP:+ [${VPS_PUBLIC_IP}]}"

  while true; do
    read -rp "  LICENSE_TOKEN (fornecido na compra da licença PRO)${license_hint}: " input
    LICENSE_TOKEN="${input:-${LICENSE_TOKEN}}"
    [[ -n "$LICENSE_TOKEN" ]] && break
    echo -e "${RED}  ✗ LICENSE_TOKEN não pode ser vazio${NC}"
  done

  while true; do
    read -rp "  IP público da VPS${ip_hint} (usado pelo gateway de voz, ex: 203.0.113.10): " input
    VPS_PUBLIC_IP="${input:-${VPS_PUBLIC_IP}}"
    [[ -n "$VPS_PUBLIC_IP" ]] && break
    echo -e "${RED}  ✗ IP da VPS não pode ser vazio${NC}"
  done

  echo ""
  echo -e "  ${BOLD}Credenciais Docker Hub (necessárias para baixar as imagens PRO):${NC}"
  echo -e "  Usuário e access token fornecidos pelo suporte SofiaCRM na compra da licença."
  echo ""

  local dh_user_hint="${DOCKERHUB_USER:+ [${DOCKERHUB_USER}]}"
  local dh_pass_hint="${DOCKERHUB_PASSWORD:+ [configurado — Enter para manter]}"

  while true; do
    read -rp "  Usuário Docker Hub${dh_user_hint}: " input
    DOCKERHUB_USER="${input:-${DOCKERHUB_USER}}"
    [[ -n "$DOCKERHUB_USER" ]] && break
    echo -e "${RED}  ✗ Usuário não pode ser vazio${NC}"
  done

  while true; do
    read -rp "  Access Token Docker Hub${dh_pass_hint}: " input
    DOCKERHUB_PASSWORD="${input:-${DOCKERHUB_PASSWORD}}"
    [[ -n "$DOCKERHUB_PASSWORD" ]] && break
    echo -e "${RED}  ✗ Token não pode ser vazio${NC}"
  done

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

# =============================================================
# EDIÇÃO
# =============================================================
CRM_EDITION=${CRM_EDITION}

# =============================================================
# ACESSO PÚBLICO — domínio e SSL
# =============================================================
CRM_DOMAIN=${CRM_DOMAIN}
ACME_EMAIL=${ACME_EMAIL}

# =============================================================
# BANCO DE DADOS — PostgreSQL
# Usuário padrão da imagem Docker: postgres (não é configurável)
# =============================================================
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# =============================================================
# CACHE — Redis
# Redis não usa nome de usuário — somente senha
# =============================================================
REDIS_PASSWORD=${REDIS_PASSWORD}

# =============================================================
# SEGURANÇA — tokens internos
# JWT_SECRET: assina os tokens de sessão dos usuários do CRM
# INTERNAL_TOKEN: autentica chamadas internas crm_api <-> whats-service
# META_CLOUD_SERVICE_TOKEN: token INTERNO entre crm_api <-> meta-cloud-service
#   (NÃO é da Meta/Facebook — é gerado por você para comunicação entre containers)
# =============================================================
JWT_SECRET=${JWT_SECRET}
INTERNAL_TOKEN=${INTERNAL_TOKEN}
META_CLOUD_SERVICE_TOKEN=${META_CLOUD_SERVICE_TOKEN}

# =============================================================
# STORAGE DE MÍDIA
# =============================================================
STORAGE_TYPE=${STORAGE_TYPE}
EOF

  if [ "$STORAGE_TYPE" == "s3" ]; then
    cat >> "$INSTALL_DIR/.env" <<EOF
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION}
AWS_S3_BUCKET_NAME=${AWS_S3_BUCKET_NAME}
AWS_S3_ENDPOINT=${AWS_S3_ENDPOINT}
AWS_S3_FORCE_PATH_STYLE=${AWS_S3_FORCE_PATH_STYLE}
EOF
  fi

  if [ "$CRM_EDITION" == "pro" ]; then
    cat >> "$INSTALL_DIR/.env" <<EOF

# =============================================================
# PRO — Licença e gateway de voz
# LICENSE_TOKEN: chave de ativação da licença Pro (fornecido na compra)
# VPS_PUBLIC_IP: IP público da VPS (usado pelo wa-call-gateway)
# DOCKERHUB_USER / DOCKERHUB_PASSWORD: credenciais para baixar imagens privadas
# =============================================================
LICENSE_TOKEN=${LICENSE_TOKEN}
VPS_PUBLIC_IP=${VPS_PUBLIC_IP}
DOCKERHUB_USER=${DOCKERHUB_USER}
DOCKERHUB_PASSWORD=${DOCKERHUB_PASSWORD}
EOF
  fi

  if [[ -n "$N8N_DOMAIN" ]]; then
    cat >> "$INSTALL_DIR/.env" <<EOF

# =============================================================
# n8n — Automação de workflows
# N8N_ENCRYPTION_KEY: chave de criptografia dos dados do n8n
# NUNCA altere após a primeira instalação!
# =============================================================
N8N_DOMAIN=${N8N_DOMAIN}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
EOF
  fi

  echo -e "${GREEN}✓ .env gravado${NC}"
}

# ── Login Docker Hub para imagens PRO ────────────────────────────────────────
docker_login_pro() {
  echo -e "${YELLOW}→ Autenticando no Docker Hub...${NC}"
  if echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USER" --password-stdin 2>&1; then
    echo -e "${GREEN}✓ Docker Hub autenticado${NC}"
  else
    echo -e "${RED}✗ Falha na autenticação Docker Hub.${NC}"
    echo -e "   Verifique usuário e senha/token em: hub.docker.com → Account Settings → Personal access tokens"
    exit 1
  fi
}

# ── Override PRO ──────────────────────────────────────────────────────────────
create_pro_override() {
  echo -e "${YELLOW}→ Criando configuração override PRO...${NC}"
  cp "$INSTALL_DIR/docker-compose.override.yml.example" "$INSTALL_DIR/docker-compose.override.yml"
  echo -e "${GREEN}✓ Override PRO criado (docker-compose.override.yml)${NC}"
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

  # Routers base do CRM
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
EOF

  # Routers n8n (adicionados apenas se N8N_DOMAIN estiver configurado)
  if [[ -n "$N8N_DOMAIN" ]]; then
    cat >> "$INSTALL_DIR/traefik/dynamic.yml" <<EOF

    n8n_editor:
      rule: "Host(\`${N8N_DOMAIN}\`)"
      entryPoints:
        - websecure
      service: n8n_editor
      tls:
        certResolver: letsencryptresolver
      priority: 1

    n8n_webhook:
      rule: "Host(\`${N8N_DOMAIN}\`) && PathPrefix(\`/webhook\`)"
      entryPoints:
        - websecure
      service: n8n_webhook
      tls:
        certResolver: letsencryptresolver
      priority: 10
EOF
  fi

  # Services base do CRM
  cat >> "$INSTALL_DIR/traefik/dynamic.yml" <<EOF

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

  # Services n8n
  if [[ -n "$N8N_DOMAIN" ]]; then
    cat >> "$INSTALL_DIR/traefik/dynamic.yml" <<EOF

    n8n_editor:
      loadBalancer:
        servers:
          - url: "http://n8n_editor:5678"

    n8n_webhook:
      loadBalancer:
        servers:
          - url: "http://n8n_webhook:5678"
EOF
  fi

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
  local edition_label="Free"
  [[ "${CRM_EDITION:-free}" == "pro" ]] && edition_label="PRO"
  echo ""
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  ✓  SofiaCRM ${edition_label} pronto!${NC}"
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

  echo -e "${BLUE}${BOLD}─── Escolha a edição ──────────────────────────────────────────${NC}"
  echo ""
  echo "    F) Free  — edição gratuita (1 tenant, sem gateway de voz)"
  echo "    P) PRO   — multi-tenant, gateway de voz (requer licença)"
  echo ""
  while true; do
    read -rp "  Edição [F/P]: " EDITION_CHOICE
    case "${EDITION_CHOICE,,}" in
      f) CRM_EDITION="free"; break ;;
      p) CRM_EDITION="pro"; break ;;
      *) echo -e "${RED}  ✗ Digite F ou P${NC}" ;;
    esac
  done
  echo ""

  collect_info

  if [ "$CRM_EDITION" == "pro" ]; then
    collect_pro_info
    docker_login_pro
  else
    LICENSE_TOKEN=""
    VPS_PUBLIC_IP=""
  fi

  generate_secrets
  create_env

  if [ "$CRM_EDITION" == "pro" ]; then
    create_pro_override
  else
    rm -f "$INSTALL_DIR/docker-compose.override.yml"
  fi

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

  # Se a instalação atual é PRO, permite atualizar LICENSE_TOKEN e VPS_PUBLIC_IP
  if [ "${CRM_EDITION:-free}" == "pro" ]; then
    collect_pro_info
  fi

  echo -e "  ${BOLD}Senhas e tokens:${NC}"
  read -rp "  Deseja regenerar todas as senhas e tokens? [s/N]: " REGEN
  echo ""
  if [[ "${REGEN,,}" == "s" ]]; then
    generate_secrets
  else
    echo -e "${GREEN}✓ Senhas e tokens mantidos${NC}"
  fi

  create_env
  if [ "$CRM_EDITION" == "pro" ]; then
    create_pro_override
  else
    rm -f "$INSTALL_DIR/docker-compose.override.yml"
  fi
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

  set -a
  # shellcheck disable=SC1091
  source "$INSTALL_DIR/.env"
  set +a

  echo ""
  echo -e "${BLUE}${BOLD}─── Atualizando SofiaCRM ──────────────────────────────────────${NC}"
  echo ""
  echo -e "${YELLOW}→ Baixando imagens mais recentes...${NC}"
  if [ "${CRM_EDITION:-free}" == "pro" ]; then
    docker_login_pro
  fi
  docker compose pull
  echo -e "${YELLOW}→ Reiniciando containers...${NC}"
  docker compose down
  docker compose up -d
  wait_crm_healthy

  # Atualiza n8n se estiver instalado
  if [[ -n "${N8N_DOMAIN:-}" ]] && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE '^n8n_editor$'; then
    echo -e "${YELLOW}→ Atualizando n8n...${NC}"
    docker compose -f "$INSTALL_DIR/docker-compose-n8n.yml" --env-file "$INSTALL_DIR/.env" pull
    docker compose -f "$INSTALL_DIR/docker-compose-n8n.yml" --env-file "$INSTALL_DIR/.env" up -d
    echo -e "${GREEN}✓ n8n atualizado${NC}"
  fi

  echo ""
  local edition_label="Free"
  [[ "${CRM_EDITION:-free}" == "pro" ]] && edition_label="PRO"
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  ✓  SofiaCRM ${edition_label} atualizado com sucesso!${NC}"
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${BOLD}Containers em execução:${NC}"
  docker ps --format "    {{.Names}}: {{.Status}}"
  echo ""
}

# ── Ação 4: Upgrade para PRO ──────────────────────────────────────────────────
action_upgrade_pro() {
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

  if [ "${CRM_EDITION:-free}" == "pro" ]; then
    echo ""
    echo -e "${YELLOW}⚠  Esta instalação já está na edição PRO.${NC}"
    echo -e "   Use a opção 3 (Editar) para alterar configurações PRO."
    echo ""
    exit 0
  fi

  echo ""
  echo -e "${BLUE}${BOLD}─── Upgrade Free → PRO ────────────────────────────────────────${NC}"
  echo ""
  echo -e "  Este upgrade irá:"
  echo -e "  ${GREEN}✓${NC} Fazer backup completo dos dados Free"
  echo -e "  ${GREEN}✓${NC} Recriar o banco com schema PRO nativo (sem migrações manuais)"
  echo -e "  ${GREEN}✓${NC} Restaurar todos os dados no novo schema"
  echo -e "  ${GREEN}✓${NC} Manter mídia, sessões WhatsApp e configurações"
  echo -e "  ${GREEN}✓${NC} Adicionar multi-tenancy, gateway de voz e recursos PRO"
  echo ""
  read -rp "  Confirmar upgrade? [s/N]: " CONFIRM_UPGRADE
  echo ""
  [[ "${CONFIRM_UPGRADE,,}" != "s" ]] && { echo -e "${YELLOW}  ✗ Upgrade cancelado.${NC}"; exit 0; }

  CRM_EDITION="pro"
  collect_pro_info
  docker_login_pro
  create_env
  create_pro_override

  # ── Fase 1: Backup ────────────────────────────────────────────────────────
  local BACKUP_TS
  BACKUP_TS=$(date +%Y%m%d_%H%M%S)
  local BACKUP_FULL="$INSTALL_DIR/backup_free_${BACKUP_TS}.dump"
  local BACKUP_DATA="$INSTALL_DIR/backup_free_${BACKUP_TS}_data.sql"
  local BACKUP_OK=false

  echo ""
  echo -e "  ${BOLD}Backup do banco de dados:${NC}"
  echo -e "  O backup completo pode levar alguns minutos dependendo do tamanho do banco."
  echo -e "  Recomendado para instalações com dados reais de produção."
  echo ""
  read -rp "  Deseja fazer backup antes do upgrade? [S/n]: " DO_BACKUP
  echo ""

  if [[ "${DO_BACKUP,,}" != "n" ]]; then
    echo -e "${YELLOW}→ Fazendo backup completo do banco Free...${NC}"
    if docker exec sofiacrm-pgvector pg_dump -U postgres -Fc crm > "$BACKUP_FULL" 2>/dev/null; then
      echo -e "${GREEN}✓ Backup completo: $BACKUP_FULL ($(du -sh "$BACKUP_FULL" | cut -f1))${NC}"
      echo -e "${YELLOW}→ Fazendo backup de dados (para restaurar no PRO)...${NC}"
      if docker exec sofiacrm-pgvector pg_dump -U postgres --data-only --disable-triggers crm > "$BACKUP_DATA" 2>/dev/null; then
        echo -e "${GREEN}✓ Backup de dados: $BACKUP_DATA${NC}"
        BACKUP_OK=true
      else
        echo -e "${YELLOW}⚠ Backup de dados falhou${NC}"
      fi
    else
      echo -e "${YELLOW}⚠ Não foi possível criar backup (PostgreSQL pode estar indisponível).${NC}"
      read -rp "   Continuar sem backup? [s/N]: " SKIP_BACKUP
      [[ "${SKIP_BACKUP,,}" != "s" ]] && { echo -e "${YELLOW}  Upgrade cancelado.${NC}"; exit 0; }
    fi
  else
    echo -e "${YELLOW}⚠ Backup ignorado. O banco Free será deletado sem possibilidade de rollback.${NC}"
  fi

  # ── Fase 2: Baixar imagens PRO ────────────────────────────────────────────
  echo -e "${YELLOW}→ Baixando imagens PRO...${NC}"
  set +e
  docker compose pull
  PULL_STATUS=$?
  set -e

  if [ "$PULL_STATUS" -ne 0 ]; then
    echo -e "${RED}✗ Falha ao baixar imagens PRO. Revertendo para edição Free...${NC}"
    CRM_EDITION="free"
    LICENSE_TOKEN=""
    VPS_PUBLIC_IP=""
    DOCKERHUB_USER=""
    DOCKERHUB_PASSWORD=""
    create_env
    rm -f "$INSTALL_DIR/docker-compose.override.yml"
    exit 1
  fi

  # ── Fase 3: Parar Free e recriar banco com schema PRO ────────────────────
  echo -e "${YELLOW}→ Parando serviços Free...${NC}"
  docker compose down

  echo -e "${YELLOW}→ Removendo banco Free (será recriado com schema PRO nativo)...${NC}"
  docker volume rm sofiacrm_postgres18_data

  echo -e "${YELLOW}→ Iniciando PostgreSQL PRO...${NC}"
  docker compose up -d pgvector
  # Aguarda postgres estar pronto
  for i in $(seq 1 30); do
    if docker exec sofiacrm-pgvector pg_isready -U postgres -d crm -q 2>/dev/null; then
      echo -e "${GREEN}✓ PostgreSQL pronto${NC}"
      break
    fi
    sleep 2
    printf "  aguardando PostgreSQL... %d/30\r" "$i"
  done

  echo -e "${YELLOW}→ Criando schema PRO via initDb (banco limpo)...${NC}"
  docker compose up -d crm_api
  wait_crm_healthy

  # ── Fase 4: Restaurar dados Free no schema PRO ────────────────────────────
  if [ "$BACKUP_OK" = true ]; then
    echo -e "${YELLOW}→ Parando crm_api para restaurar dados...${NC}"
    docker compose stop crm_api

    echo -e "${YELLOW}→ Restaurando dados Free no schema PRO...${NC}"
    if docker exec -i sofiacrm-pgvector psql -U postgres -d crm < "$BACKUP_DATA" > /dev/null 2>&1; then
      echo -e "${GREEN}✓ Dados restaurados com sucesso${NC}"
    else
      echo -e "${YELLOW}⚠ Restauração com avisos — verificando integridade...${NC}"
      # Verifica se pelo menos a tabela tenants tem dados
      TENANT_COUNT=$(docker exec sofiacrm-pgvector psql -U postgres -d crm -tAc "SELECT COUNT(*) FROM tenants" 2>/dev/null || echo "0")
      if [ "$TENANT_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Dados presentes ($TENANT_COUNT tenant(s) encontrado(s))${NC}"
      else
        echo -e "${RED}✗ Restauração falhou. Banco PRO iniciará vazio.${NC}"
        echo -e "   Backup completo disponível para rollback: $BACKUP_FULL"
      fi
    fi

    echo -e "${YELLOW}→ Reiniciando crm_api (initDb migra user_tenants com dados existentes)...${NC}"
    docker compose up -d crm_api
    wait_crm_healthy

    echo -e "${YELLOW}→ Verificando licença PRO nos logs...${NC}"
    if docker logs crm_api 2>&1 | grep -qi "licen.*v.*lid\|Token de licen\|válido e ativo"; then
      echo -e "${GREEN}✓ Licença PRO validada com sucesso${NC}"
    else
      echo -e "${YELLOW}⚠ Não foi possível confirmar a licença nos logs.${NC}"
      echo -e "   Verifique com: docker logs crm_api | grep -i licen${NC}"
    fi
  fi

  # ── Fase 5: Subir todos os serviços PRO ──────────────────────────────────
  echo -e "${YELLOW}→ Subindo todos os serviços PRO...${NC}"
  docker compose up -d

  if [ "$BACKUP_OK" = true ]; then
    echo ""
    echo -e "  ${YELLOW}Backups salvos (para rollback se necessário):${NC}"
    echo -e "  • Completo: $BACKUP_FULL"
    echo -e "  • Dados:    $BACKUP_DATA"
  fi

  print_summary
}

# ── Coleta de informações n8n ────────────────────────────────────────────────────
collect_n8n_info() {
  echo ""
  echo -e "${BLUE}${BOLD}─── Configuração n8n ───────────────────────────────────────────${NC}"
  echo ""
  echo -e "  O n8n será exposto em um subdomínio próprio (ex: n8n.seudominio.com)."
  echo -e "  Certifique-se que o DNS deste subdomínio já aponta para o IP desta VPS."
  echo ""

  local n8n_hint="${N8N_DOMAIN:+ [${N8N_DOMAIN}]}"
  while true; do
    read -rp "  Domínio do n8n${n8n_hint} (ex: n8n.seudominio.com): " input
    N8N_DOMAIN="${input:-${N8N_DOMAIN}}"
    [[ -n "$N8N_DOMAIN" ]] && break
    echo -e "${RED}  ✗ Domínio não pode ser vazio${NC}"
  done

  if [[ -z "$N8N_ENCRYPTION_KEY" ]]; then
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
    echo -e "${GREEN}✓ N8N_ENCRYPTION_KEY gerada automaticamente${NC}"
  else
    echo -e "${GREEN}✓ N8N_ENCRYPTION_KEY mantida do .env${NC}"
  fi

  echo ""
}

# ── Ação 5: Instalar n8n ────────────────────────────────────────────────────
action_instalar_n8n() {
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo -e "${RED}✗ Arquivo .env não encontrado. Use a opção 1 para instalar o SofiaCRM primeiro.${NC}"
    exit 1
  fi

  echo -e "${YELLOW}→ Carregando configuração atual...${NC}"
  set -a
  # shellcheck disable=SC1091
  source "$INSTALL_DIR/.env"
  set +a

  if ! docker network ls --format '{{.Name}}' | grep -q '^sofiacrm_net$'; then
    echo -e "${RED}✗ Rede sofiacrm_net não encontrada.${NC}"
    echo -e "   Certifique-se que o SofiaCRM está em execução antes de instalar o n8n."
    exit 1
  fi

  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE '^n8n$|^n8n_editor$'; then
    echo ""
    echo -e "${YELLOW}⚠  n8n já instalado.${NC}"
    echo -e "   ${YELLOW}Nota: Se veio de uma versão anterior (single-container), os dados do${NC}"
    echo -e "   ${YELLOW}SQLite não serão migrados. Exporte os workflows antes de continuar.${NC}"
    read -rp "  Deseja reconfigurar e reiniciar o n8n? [s/N]: " CONFIRM_N8N
    echo ""
    [[ "${CONFIRM_N8N,,}" != "s" ]] && { echo -e "${YELLOW}  Cancelado.${NC}"; exit 0; }
    # Para e remove container legado (instalação single-container anterior)
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^n8n$'; then
      echo -e "${YELLOW}→ Removendo container n8n legado...${NC}"
      docker stop n8n 2>/dev/null || true
      docker rm   n8n 2>/dev/null || true
    fi
    docker compose -f "$INSTALL_DIR/docker-compose-n8n.yml" --env-file "$INSTALL_DIR/.env" down 2>/dev/null || true
  fi

  echo ""
  echo -e "${BLUE}${BOLD}─── Instalando n8n ─────────────────────────────────────────────${NC}"
  collect_n8n_info

  # Persiste as variáveis n8n no .env (remove bloco anterior se existir, depois adiciona)
  # Remove linhas antigas do bloco n8n se já existirem
  if grep -q '^N8N_DOMAIN=' "$INSTALL_DIR/.env" 2>/dev/null; then
    # Reescreve .env sem as linhas n8n (serão re-adicionadas abaixo)
    grep -v '^N8N_DOMAIN=\|^N8N_ENCRYPTION_KEY=\|^# n8n \|^# N8N_ENCRYPTION_KEY:\|^# NUNCA altere após' "$INSTALL_DIR/.env" > "$INSTALL_DIR/.env.tmp"
    mv "$INSTALL_DIR/.env.tmp" "$INSTALL_DIR/.env"
  fi
  cat >> "$INSTALL_DIR/.env" <<EOF

# n8n — Automação de workflows
# N8N_ENCRYPTION_KEY: chave de criptografia dos dados do n8n (gerada automaticamente)
N8N_DOMAIN=${N8N_DOMAIN}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
EOF

  # Atualiza dynamic.yml do Traefik para incluir rota n8n
  setup_traefik
  docker compose restart traefik

  # Cria banco n8n_queue no PostgreSQL se não existir
  echo -e "${YELLOW}→ Criando banco n8n_queue no PostgreSQL (se não existir)...${NC}"
  docker exec sofiacrm-pgvector psql -U postgres -tc \
    "SELECT 1 FROM pg_database WHERE datname='n8n_queue'" \
    | grep -q 1 || docker exec sofiacrm-pgvector psql -U postgres -c "CREATE DATABASE n8n_queue;"
  echo -e "${GREEN}✓ Banco n8n_queue pronto${NC}"

  echo -e "${YELLOW}→ Subindo n8n...${NC}"
  docker compose -f "$INSTALL_DIR/docker-compose-n8n.yml" --env-file "$INSTALL_DIR/.env" pull
  docker compose -f "$INSTALL_DIR/docker-compose-n8n.yml" --env-file "$INSTALL_DIR/.env" up -d

  echo ""
  echo -e "${YELLOW}→ Aguardando n8n inicializar...${NC}"
  local n8n_ready=false
  for i in $(seq 1 20); do
    if docker exec n8n_editor wget -q --tries=1 --spider http://localhost:5678/ 2>/dev/null; then
      echo -e "${GREEN}✓ n8n pronto!${NC}"
      n8n_ready=true
      break
    fi
    sleep 3
    printf "  tentativa %d/20...\r" "$i"
  done
  if [ "$n8n_ready" = false ]; then
    echo -e "${YELLOW}⚠ n8n ainda inicializando. Verifique com: docker logs n8n_editor --tail 20${NC}"
  fi

  echo ""
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  ✓  n8n instalado!${NC}"
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${BOLD}➜ Acesse o n8n em:${NC}"
  echo -e "     ${CYAN}https://${N8N_DOMAIN}${NC}"
  echo ""
  echo -e "  ${BOLD}➜ Chamadas internas de webhook (CRM → n8n):${NC}"
  echo -e "     ${CYAN}http://n8n_webhook:5678/webhook/SEU_PATH${NC}"
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
  2) action_upgrade_pro ;;
  3) action_editar ;;
  4) action_atualizar ;;
  5) action_instalar_n8n ;;
esac
