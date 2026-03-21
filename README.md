# SofiaCRM — Instalador Docker

Instalador automático do [Sofia CRM](https://sofiacrm.com.br) para VPS Linux com Docker.  
Versão do script: **v1.3**

---

## Pré-requisitos

- VPS **Ubuntu 22.04 ou 24.04 LTS — AMD64 (x86_64)**
- Domínio ou subdomínio com DNS apontando para o IP da VPS (aguarde a propagação)
- Acesso root

> O script instala o Docker automaticamente caso não esteja presente.

---

## Início rápido

```sh
git clone https://github.com/leostrongGG/sofiacrm-install.git /root/SofiaCRM
cd /root/SofiaCRM
chmod +x sofia_install.sh
./sofia_install.sh
```

O script exibe um menu com **5 opções**:

```
  1) Instalar SofiaCRM        — nova instalação (Free ou PRO)
  2) Upgrade para SofiaCRM Pro — fazer upgrade da edição Free para PRO
  3) Editar Instalação         — alterar configurações e reiniciar
  4) Atualizar SofiaCRM        — atualizar imagens para a versão mais recente
  5) Instalar n8n              — automação de workflows (opcional)
```

Para uma **nova instalação**, escolha a opção `1`. O script vai perguntar:

1. **Edição**: `F` para Free ou `P` para PRO
2. **Domínio** do CRM (ex: `crm.seudominio.com`)
3. **E-mail** para o certificado SSL (Let's Encrypt)
4. **Storage de mídia**: local (disco da VPS) ou S3 (Backblaze B2, AWS, R2...)

Tudo o mais — senhas, tokens, banco de dados — é gerado e configurado automaticamente.

No final você verá a URL para criar o primeiro usuário administrador:
```
https://crm.seudominio.com/pages/install.html
```

---

## Opções do script

### Opção 1 — Instalar Free ou PRO

Nova instalação completa. Pergunta a edição desejada (`F` = Free / `P` = PRO), instala Docker se necessário, coleta domínio e e-mail, gera todas as senhas, configura Traefik e sobe os containers. A edição PRO requer `LICENSE_TOKEN` e credenciais Docker Hub fornecidas na compra.

### Opção 2 — Upgrade para PRO

Atualiza uma instalação Free existente para a edição PRO **sem perder dados**. Requer:
- `LICENSE_TOKEN` — fornecido por e-mail na compra da licença
- Usuário e access token do Docker Hub — fornecidos junto com a licença (imagens privadas)
- IP público da VPS — para o gateway de chamadas de voz
- Portas UDP/TCP **30000–30100** abertas no firewall da VPS

O upgrade executa as seguintes etapas automaticamente:
1. **(Opcional)** Backup completo do banco (`pg_dump`)
2. Remove o volume PostgreSQL antigo (schema Free incompatível com PRO)
3. Sobe o PRO com `initDb` para criar o schema nativo PRO
4. Restaura os dados do backup (tenants, usuários, contatos, histórico)
5. Valida a licença e verifica integridade dos dados

Mídia e sessões WhatsApp são preservados (volumes separados, não são tocados).

### Opção 3 — Editar instalação

Altera qualquer configuração (domínio, e-mail, storage, tokens PRO) e reinicia os containers com as novas definições. Para instalações PRO, permite também atualizar `LICENSE_TOKEN` e `VPS_PUBLIC_IP`.

### Opção 4 — Atualizar

Baixa as imagens Docker mais recentes (`docker compose pull`) e reinicia os containers. Se o n8n estiver instalado, também o atualiza.

### Opção 5 — Instalar n8n

Instala o [n8n](https://n8n.io) (automação de workflows) no mesmo servidor, integrado ao Traefik existente (HTTPS automático) e na mesma rede Docker (`sofiacrm_net`). Requer um subdomínio próprio (ex: `n8n.seudominio.com`).

---

## Estrutura de arquivos

```
/root/SofiaCRM/
├── sofia_install.sh                    ← script principal (v1.3)
├── .env                                ← gerado pelo script (NUNCA commitar!)
├── .env.example                        ← modelo de variáveis
├── .gitignore
├── docker-compose.yml                  ← 6 serviços base (edição Free)
├── docker-compose.override.yml         ← gerado no upgrade PRO (merge automático)
├── docker-compose.override.yml.example ← template PRO (source do override)
├── docker-compose-n8n.yml              ← compose separado para o n8n (opcional)
├── INSTALLATION_SUMMARY.md             ← guia de instalação manual detalhado
└── traefik/
    ├── traefik.yml             ← gerado pelo script (com seu e-mail)
    ├── traefik.yml.example     ← modelo com placeholders
    ├── dynamic.yml             ← gerado pelo script (com seu domínio + rotas)
    ├── dynamic.yml.example     ← modelo com placeholders
    └── acme.json               ← gerado pelo Traefik (certificados SSL)
```

---

## Variáveis do `.env`

| Variável | Edição | Descrição |
|---|---|---|
| `CRM_EDITION` | Todas | `free` ou `pro` — definido automaticamente pelo script |
| `CRM_DOMAIN` | Todas | Domínio do CRM |
| `ACME_EMAIL` | Todas | E-mail para Let's Encrypt |
| `POSTGRES_USER` | Todas | Sempre `postgres` (superusuário padrão da imagem Docker) |
| `POSTGRES_PASSWORD` | Todas | Senha do PostgreSQL (gerada automaticamente) |
| `REDIS_PASSWORD` | Todas | Senha do Redis (gerada automaticamente) |
| `JWT_SECRET` | Todas | Chave de autenticação JWT (gerada automaticamente) |
| `INTERNAL_TOKEN` | Todas | Token interno entre serviços (gerado automaticamente) |
| `META_CLOUD_SERVICE_TOKEN` | Todas | Token interno crm_api ↔ meta-cloud-service (gerado automaticamente) |
| `STORAGE_TYPE` | Todas | `local` ou `s3` |
| `AWS_*` | Todas | Credenciais S3 — só necessário se `STORAGE_TYPE=s3` |
| `LICENSE_TOKEN` | PRO | Token de ativação da licença (fornecido na compra) |
| `VPS_PUBLIC_IP` | PRO | IP público da VPS para o gateway de voz |
| `DOCKERHUB_USER` | PRO | Usuário Docker Hub para baixar imagens privadas (fornecido na compra) |
| `DOCKERHUB_PASSWORD` | PRO | Access token Docker Hub (fornecido na compra — pode expirar, peça novo ao suporte) |
| `N8N_DOMAIN` | n8n | Subdomínio do n8n (ex: `n8n.seudominio.com`) |
| `N8N_ENCRYPTION_KEY` | n8n | Chave de criptografia do n8n (gerada automaticamente — nunca alterar após instalar) |

> **Sobre `META_CLOUD_SERVICE_TOKEN`:** Token gerado por você para proteger a comunicação interna entre containers. Não tem relação com credenciais da Meta/Facebook.

> **Sobre usuários:** O PostgreSQL usa sempre `postgres`. O Redis não usa nome de usuário, apenas senha.

---

## Instalação manual

Para instalar passo a passo sem o script, consulte o [INSTALLATION_SUMMARY.md](INSTALLATION_SUMMARY.md).

---

## Licença

MIT
