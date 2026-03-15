# SofiaCRM — Instalador Docker

Instalador automático do [Sofia CRM](https://sofiacrm.com.br) para VPS Linux com Docker.

---

## Pré-requisitos

- VPS **Ubuntu 22.04 ou 24.04 LTS — AMD64 (x86_64)**
- Domínio ou subdomínio com DNS apontando para o IP da VPS (aguarde a propagação)
- Acesso root

> O script instala o Docker automaticamente caso não esteja presente.

---

## Instalação rápida

```sh
git clone https://github.com/leostrongGG/sofiacrm-install.git /root/SofiaCRM
cd /root/SofiaCRM
chmod +x sofia_install.sh
./sofia_install.sh
```

O script vai perguntar:
1. **Domínio** do CRM (ex: `crm.seudominio.com`)
2. **E-mail** para o certificado SSL (Let's Encrypt)
3. **Storage de mídia**: local (disco da VPS) ou S3 (Backblaze B2, AWS, R2...)

Tudo o mais — senhas, tokens, banco de dados — é gerado e configurado automaticamente.

No final você verá a URL para criar o primeiro usuário administrador:
```
https://crm.seudominio.com/pages/install.html
```

---

## O que o script faz

| Passo | Ação |
|---|---|
| 1 | Verifica arquitetura AMD64 |
| 2 | Instala Docker se necessário |
| 3 | Pergunta domínio, e-mail e tipo de storage |
| 4 | Gera automaticamente todas as senhas e tokens |
| 5 | Cria o arquivo `.env` |
| 6 | Gera configuração do Traefik com seu domínio e e-mail |
| 7 | Sobe todos os serviços com um único `docker compose up -d` |
| 8 | Aguarda o CRM inicializar e exibe a URL de acesso |

> O banco de dados `crm` é criado automaticamente pelo PostgreSQL na primeira inicialização.

---

## Estrutura de arquivos

```
/root/SofiaCRM/
├── sofia_install.sh            ← script de instalação
├── .env                        ← criado pelo script (NÃO commitar!)
├── .env.example                ← modelo de variáveis
├── .gitignore
├── docker-compose.yml          ← todos os serviços em um único arquivo
├── INSTALLATION_SUMMARY.md     ← guia de instalação manual detalhado
└── traefik/
    ├── traefik.yml             ← gerado pelo script (com seu e-mail)
    ├── traefik.yml.example     ← modelo com placeholders
    ├── dynamic.yml             ← gerado pelo script (com seu domínio)
    ├── dynamic.yml.example     ← modelo com placeholders
    └── acme.json               ← gerado pelo Traefik (certificados SSL)
```

---

## Variáveis do `.env`

| Variável | Descrição |
|---|---|
| `CRM_DOMAIN` | Domínio do CRM |
| `ACME_EMAIL` | E-mail para Let's Encrypt |
| `POSTGRES_USER` | Usuário do PostgreSQL (`postgres`, padrão da imagem) |
| `POSTGRES_PASSWORD` | Senha do PostgreSQL (gerada automaticamente) |
| `REDIS_PASSWORD` | Senha do Redis (gerada automaticamente) |
| `JWT_SECRET` | Chave de autenticação JWT (gerada automaticamente) |
| `INTERNAL_TOKEN` | Token interno crm_api ↔ whats-service (gerado automaticamente) |
| `META_CLOUD_SERVICE_TOKEN` | Token interno crm_api ↔ meta-cloud-service (gerado automaticamente) |
| `STORAGE_TYPE` | `local` ou `s3` |

> **Sobre `META_CLOUD_SERVICE_TOKEN`:** É um token que **você gera** para proteger a comunicação interna entre os dois containers Docker. Não tem relação com credenciais da Meta/Facebook — as credenciais do WhatsApp Business são configuradas depois dentro da interface do CRM.

> **Sobre usuários:** O PostgreSQL usa sempre o usuário `postgres` (superusuário padrão da imagem). O Redis não usa nome de usuário, apenas senha.

---

## Instalação manual

Para instalar passo a passo sem o script, consulte o [INSTALLATION_SUMMARY.md](INSTALLATION_SUMMARY.md).

---

## Licença

MIT
