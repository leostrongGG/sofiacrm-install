# SofiaCRM — Guia de Instalação Completo (Docker, sem Swarm)

Guia testado em **Ubuntu 24.04 LTS AMD64** com **Docker 29+** e **Docker Compose v2**.

> **Recomendado:** Use o script `sofia_install.sh` para instalar automaticamente.  
> Este documento descreve a instalação manual passo a passo.

> **Edições disponíveis:**  
> **Free** — instalação base, opção 1 do script.  
> **PRO** — upgrade sobre o Free, opção 2 do script. Requer `LICENSE_TOKEN` (fornecido na compra).

---

## ⚠️ Pré-requisitos obrigatórios

- **Arquitetura**: AMD64 (x86_64). As imagens do SofiaCRM **não funcionam em ARM**.
- **Docker Engine** instalado (v20+, recomendado v29+).
- **Docker Compose v2** (comando `docker compose`, não `docker-compose`).
- **Domínio/subdomínio** com DNS apontando para o IP da VPS (ex: `crm.seudominio.com`).
- Usuário `root` ou com permissão no grupo `docker`.

---

## Esclarecimentos importantes

### Usuários e senhas

| Serviço | Usuário | Observação |
|---|---|---|
| PostgreSQL | `postgres` | Superusuário padrão da imagem Docker — não é configurável, sempre `postgres` |
| Redis | *(sem usuário)* | Redis não usa nome de usuário, apenas senha via `requirepass` |
| Traefik | *(sem usuário)* | Não requer autenticação nesta configuração |

### Sobre o `META_CLOUD_SERVICE_TOKEN`

Este token **não vem da Meta/Facebook**. É um token que **você mesmo gera** (com `openssl rand -hex 32`) para proteger a comunicação interna entre os containers `crm_api` e `meta-cloud-service`. As credenciais reais do WhatsApp Business são configuradas depois dentro da interface do CRM.

### Sobre os arquivos `traefik/traefik.yml` e `traefik/dynamic.yml`

Estes arquivos são lidos **diretamente pelo Traefik** e **não suportam variáveis do `.env`**. O domínio e e-mail precisam estar escritos diretamente neles. O script `sofia_install.sh` os gera automaticamente. Na instalação manual, substitua os placeholders pelos seus valores reais.

### Sobre o `traefik/acme.json`

Este arquivo começa **vazio** e é preenchido automaticamente pelo Traefik ao solicitar o certificado SSL ao Let's Encrypt na primeira requisição HTTPS. Está no `.gitignore` e nunca deve ser commitado.

### Sobre o banco de dados `crm`

O banco é criado **automaticamente** pelo PostgreSQL na primeira inicialização, via a variável de ambiente `POSTGRES_DB: crm` definida no `docker-compose.yml`. Não é necessário nenhum `CREATE DATABASE` manual.

---

## Ordem de inicialização

O `docker-compose.yml` usa `depends_on` com healthchecks para garantir a ordem correta automaticamente:

```
Traefik             ──→  sobe imediatamente
PostgreSQL          ──→  sobe imediatamente, cria banco 'crm' automaticamente
Redis               ──→  sobe imediatamente
crm_api             ──→  aguarda PostgreSQL healthy + Redis healthy
whats-service       ──→  aguarda crm_api healthy
meta-cloud-service  ──→  aguarda crm_api healthy
```

---

## Passo 1 — Gerar chaves seguras

Gere cada chave individualmente com o comando abaixo e anote os valores:

```sh
openssl rand -hex 32
```

Você vai precisar de **5 valores**:

| Variável | Descrição |
|---|---|
| `POSTGRES_PASSWORD` | Senha do banco de dados |
| `REDIS_PASSWORD` | Senha do Redis |
| `JWT_SECRET` | Chave de autenticação JWT |
| `INTERNAL_TOKEN` | Token interno entre serviços |
| `META_CLOUD_SERVICE_TOKEN` | Token de comunicação interno (não é da Meta) |

---

## Passo 2 — Criar o arquivo `.env`

Crie `/root/SofiaCRM/.env` com o conteúdo abaixo, substituindo os valores:

```env
CRM_DOMAIN=crm.seudominio.com
ACME_EMAIL=seuemail@dominio.com

POSTGRES_USER=postgres
POSTGRES_PASSWORD=SENHA_POSTGRES

REDIS_PASSWORD=SENHA_REDIS

JWT_SECRET=SEU_JWT_SECRET
INTERNAL_TOKEN=SEU_INTERNAL_TOKEN
META_CLOUD_SERVICE_TOKEN=SEU_META_CLOUD_TOKEN

STORAGE_TYPE=local
```

> Para usar S3 (Backblaze B2, AWS, R2, MinIO), adicione também:
> ```env
> STORAGE_TYPE=s3
> AWS_ACCESS_KEY_ID=...
> AWS_SECRET_ACCESS_KEY=...
> AWS_REGION=...
> AWS_S3_BUCKET_NAME=...
> AWS_S3_ENDPOINT=https://...
> AWS_S3_FORCE_PATH_STYLE=true
> ```

---

## Passo 3 — Configurar o Traefik

Crie a pasta e o arquivo de certificados:

```sh
mkdir -p /root/SofiaCRM/traefik
touch /root/SofiaCRM/traefik/acme.json
chmod 600 /root/SofiaCRM/traefik/acme.json
```

Crie `/root/SofiaCRM/traefik/traefik.yml` substituindo `SEU_EMAIL`:

```yaml
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
      email: SEU_EMAIL@dominio.com
      storage: /acme/acme.json

providers:
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true

log:
  level: INFO

accessLog: {}
```

Crie `/root/SofiaCRM/traefik/dynamic.yml` substituindo `SEU_DOMINIO`:

```yaml
http:
  routers:
    crm_api:
      rule: "Host(`SEU_DOMINIO`)"
      entryPoints:
        - websecure
      service: crm_api
      tls:
        certResolver: letsencryptresolver
      priority: 1

    meta_webhook:
      rule: "Host(`SEU_DOMINIO`) && PathPrefix(`/api/webhooks/meta/whatsapp`)"
      entryPoints:
        - websecure
      service: meta_cloud
      tls:
        certResolver: letsencryptresolver
      priority: 20

    meta_cloud_api:
      rule: "Host(`SEU_DOMINIO`) && PathPrefix(`/api/meta-cloud`)"
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
```

> ⚠️ **Importante:** Não use o provider `docker` do Traefik com Docker Engine 29+ — incompatibilidade de versão da API Docker. Use sempre o provider `file` com `dynamic.yml` como mostrado acima.

---

## Passo 4 — Subir todos os serviços

Com o `.env` e os arquivos Traefik prontos, um único comando sobe tudo:

```sh
cd /root/SofiaCRM
docker compose up -d
```

O Docker Compose respeitará automaticamente a ordem via `depends_on` + healthchecks. Aguarde todos os containers ficarem `Up`:

```sh
docker ps --format '{{.Names}}: {{.Status}}'
```

Saída esperada (após ~60s):
```
traefik:           Up X minutes
sofiacrm-pgvector: Up X minutes (healthy)
sofiacrm-redis:    Up X minutes (healthy)
crm_api:           Up X minutes (healthy)
crm_whatsmeow:     Up X minutes
crm_meta_cloud:    Up X minutes
```

---

## Passo 5 — Criar o superadmin

Acesse pelo navegador:

```
https://SEU_DOMINIO/pages/install.html
```

Preencha: Nome, Sobrenome, Email e Senha, e clique em **Criar Super Administrador**.

> **Se a página mostrar "Failed to fetch":** o Traefik ainda não está corretamente configurado. Crie o superadmin via curl diretamente no servidor:
>
> ```sh
> curl -s -X POST http://localhost:3000/api/install/setup \
>   -H "Content-Type: application/json" \
>   -d '{"firstName":"Seu","lastName":"Nome","email":"email@dominio.com","password":"SuaSenha","confirmPassword":"SuaSenha"}'
> ```

---

## Passo 6 — Verificação final

```sh
# Todos os containers rodando
docker ps --format '{{.Names}}: {{.Status}}'

# HTTPS respondendo
curl -sI https://SEU_DOMINIO | head -3

# Logs do CRM
docker logs crm_api --tail 10
```

---

## Estrutura de arquivos

```
/root/SofiaCRM/
├── sofia_install.sh                    ← script de instalação automática (v1.2)
├── .env                                ← criado por você (NUNCA commitar!)
├── .env.example                        ← modelo de variáveis
├── .gitignore
├── docker-compose.yml                  ← 6 serviços base (edição Free)
├── docker-compose.override.yml         ← criado automaticamente no upgrade PRO
├── docker-compose.override.yml.example ← template PRO (editavel, origem do override)
├── docker-compose-n8n.yml              ← compose separado para o n8n (opcional)
└── traefik/
    ├── traefik.yml             ← criado por você (contém seu e-mail)
    ├── traefik.yml.example     ← modelo com placeholders
    ├── dynamic.yml             ← criado por você (contém seu domínio e rotas)
    ├── dynamic.yml.example     ← modelo com placeholders
    └── acme.json               ← gerado automaticamente pelo Traefik
```

---

## Erros comuns e soluções

| Erro | Causa | Solução |
|---|---|---|
| `exec format error` | VPS não é AMD64 | Use uma VPS x86_64 |
| `password authentication failed` | Senha errada no `DATABASE_URL` | Confira `.env` — `POSTGRES_PASSWORD` deve coincidir |
| `Failed to fetch` na página de install | Traefik não está ativo ou HTTPS não funciona | Verifique `docker logs traefik` |
| `client version 1.24 is too old` no Traefik | Provider Docker incompatível com Docker 29+ | Use o provider `file` conforme este guia |
| `Eviction policy` warning no Redis | `allkeys-lru` configurado | Troque para `noeviction` |
| `crm_api` em restart loop | PostgreSQL ou Redis ainda não healthy | Aguarde os healthchecks — `depends_on` garante a ordem |

---

## Upgrade Free → PRO (manual)

> O script `sofia_install.sh` executa este processo automaticamente via **opção 2**.  
> Siga as etapas abaixo apenas se quiser fazer o upgrade manualmente.

### O que o upgrade faz

- Troca a imagem `sofiacrm-community:latest` → `sofiacrm-pro:latest`
- Adiciona o serviço `wa-call-gateway` (chamadas de voz via WhatsApp)
- **Mantém** todos os dados: banco PostgreSQL, volumes Redis, mídia, sessões WhatsApp
- **Mantém** todas as senhas e tokens existentes (não precisa regenerar)

### Pré-requisitos PRO

- Instalação Free funcionando
- `LICENSE_TOKEN` — fornecido por e-mail na compra da licença PRO
- IP público da VPS — usado pelo `wa-call-gateway` para roteamento de chamadas
- Portas UDP/TCP **30000-30100** abertas no firewall da VPS

### Passo 1 — Adicionar variáveis PRO ao `.env`

```env
# Adicione ao final do .env existente
CRM_EDITION=pro
LICENSE_TOKEN=seu_token_de_licenca
VPS_PUBLIC_IP=203.0.113.10
```

### Passo 2 — Criar `docker-compose.override.yml`

Crie o arquivo `/root/SofiaCRM/docker-compose.override.yml`:

```yaml
services:
  crm_api:
    image: inovanode/sofiacrm-pro:latest
    environment:
      LICENSE_TOKEN: ${LICENSE_TOKEN}

  wa-call-gateway:
    image: inovanode/sofiacrm-gateway:latest
    container_name: crm_wa_gateway
    restart: always
    depends_on:
      crm_api:
        condition: service_healthy
    environment:
      PORT: 8091
      GATEWAY_UDP_MIN: 30000
      GATEWAY_UDP_MAX: 30100
      GATEWAY_PUBLIC_IP: ${VPS_PUBLIC_IP}
      CRM_API_URL: http://crm_api:3000
      INTERNAL_WEBHOOK_TOKEN: ${INTERNAL_TOKEN}
    ports:
      - "30000-30100:30000-30100/udp"
      - "30000-30100:30000-30100/tcp"
    networks:
      - sofiacrm_net
```

> O Docker Compose lê `docker-compose.yml` + `docker-compose.override.yml` automaticamente,
> sem nenhuma flag adicional.

### Passo 3 — Aplicar o upgrade

```sh
cd /root/SofiaCRM
docker compose pull          # baixa imagens PRO
docker compose down          # para os containers
docker compose up -d         # sobe com override aplicado
```

### Verificação

```sh
docker ps --format '{{.Names}}: {{.Status}}'
```

Saída esperada após upgrade (adicionado `crm_wa_gateway`):
```
traefik:            Up X minutes
sofiacrm-pgvector:  Up X minutes (healthy)
sofiacrm-redis:     Up X minutes (healthy)
crm_api:            Up X minutes (healthy)
crm_whatsmeow:      Up X minutes
crm_meta_cloud:     Up X minutes
crm_wa_gateway:     Up X minutes
```

### Erros comuns no upgrade

| Erro | Causa | Solução |
|---|---|---|
| `crm_api` não inicia após upgrade | `LICENSE_TOKEN` inválido ou ausente | Confira o token no `.env` e no override |
| `crm_wa_gateway` não conecta | IP da VPS incorreto | Confira `VPS_PUBLIC_IP` no `.env` |
| Portas 30000-30100 recusadas | Firewall bloqueando | Abra UDP/TCP 30000-30100 no firewall da VPS |

---

## Instalar n8n (opcional)

> O script `sofia_install.sh` executa este processo automaticamente via **opção 5**.  
> Siga as etapas abaixo apenas se quiser instalar o n8n manualmente.

### Pré-requisitos n8n

- SofiaCRM (Free ou PRO) instalado e em execução
- Subdomínio exclusivo para o n8n (ex: `n8n.crm.seudominio.com`) com DNS apontando para a mesma VPS
- Chave de criptografia gerada com `openssl rand -hex 32` — **nunca altere após a primeira instalação**

### Passo 1 — Adicionar variáveis n8n ao `.env`

```env
# Adicione ao final do .env existente
N8N_DOMAIN=n8n.crm.seudominio.com
N8N_ENCRYPTION_KEY=sua_chave_gerada_com_openssl
```

### Passo 2 — Adicionar rota n8n ao `traefik/dynamic.yml`

Adicione dentro de `http.routers`:

```yaml
    n8n:
      rule: "Host(`n8n.crm.seudominio.com`)"
      entryPoints:
        - websecure
      service: n8n
      tls:
        certResolver: letsencryptresolver
      priority: 1
```

E dentro de `http.services`:

```yaml
    n8n:
      loadBalancer:
        servers:
          - url: "http://n8n:5678"
```

Reinicie o Traefik para aplicar:

```sh
docker compose restart traefik
```

### Passo 3 — Subir o n8n

```sh
cd /root/SofiaCRM
docker compose -f docker-compose-n8n.yml --env-file .env pull
docker compose -f docker-compose-n8n.yml --env-file .env up -d
```

### Verificação

```sh
docker ps --format '{{.Names}}: {{.Status}}' | grep n8n
```

Acesse em: `https://n8n.crm.seudominio.com`

### Erros comuns no n8n

| Erro | Causa | Solução |
|---|---|---|
| `502 Bad Gateway` | n8n ainda inicializando | Aguarde ~30s e recarregue |
| Erro de criptografia após reiniciar | `N8N_ENCRYPTION_KEY` foi alterada | Restaure a chave original do `.env` |
| SSL não gerado | DNS do subdomínio não propagado | Aguarde a propagação e reinicie o Traefik |
