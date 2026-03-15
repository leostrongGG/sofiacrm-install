# SofiaCRM — Guia de Instalação Completo (Docker, sem Swarm)

Guia testado em **Ubuntu 24.04 LTS AMD64** com **Docker 29+** e **Docker Compose v2**.

> **Recomendado:** Use o script `sofia_install.sh` para instalar automaticamente.  
> Este documento descreve a instalação manual passo a passo.

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
├── sofia_install.sh            ← script de instalação automática
├── .env                        ← criado por você (NUNCA commitar!)
├── .env.example                ← modelo de variáveis
├── .gitignore
├── docker-compose.yml          ← todos os 6 serviços em um arquivo
└── traefik/
    ├── traefik.yml             ← criado por você (contém seu e-mail)
    ├── traefik.yml.example     ← modelo com placeholders
    ├── dynamic.yml             ← criado por você (contém seu domínio)
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
