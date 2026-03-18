# Onix Saude | Wizard de Onboarding de Documentos

Frontend de onboarding com wizard de tela unica, envio de documentos e proxy protegido para o n8n via `.env`.

## O que mudou

- o navegador nao recebe mais a URL real do webhook
- o formulario envia para `/api/submit`
- o servidor local le `WEBHOOK_URL` e headers secretos do arquivo `.env`
- o `Painel admin` continua disponivel para consulta local dos protocolos arquivados neste navegador

## Como rodar

1. Copie o arquivo de exemplo:

```bash
cp .env.example .env
```

2. Edite o `.env` com a URL do seu webhook do n8n:

```env
PORT=4173
WEBHOOK_URL=https://seu-n8n/webhook/onix-documentos
WEBHOOK_AUTH_HEADER_NAME=
WEBHOOK_AUTH_HEADER_VALUE=
PROXY_TIMEOUT_MS=45000
```

3. Inicie o servidor:

```bash
node server.js
```

4. Abra:

```text
http://127.0.0.1:4173/
```

## Contrato do proxy

O frontend envia `multipart/form-data` para:

- `POST /api/submit`

O servidor repassa o mesmo payload para o `WEBHOOK_URL` do `.env`.

## Campos enviados ao n8n

Campos texto:

- `source_app`
- `submission_id`
- `submitted_at`
- `payload_json`
- `titular_nome`
- `titular_cpf`
- `titular_celular`
- `possui_dependentes`
- `quantidade_dependentes`
- `regime_contratacao`
- `matricula`
- `assinatura_nome`

Campos de arquivo:

- `identidade_cpf`
- `contracheque`
- `comprovante_residencia`
- `declaracao_saude`

## Endpoints locais

- `GET /api/health`
- `POST /api/submit`

## Observacoes

- `.env` esta no `.gitignore`
- se `WEBHOOK_URL` estiver vazio, o servidor responde em modo local
- os anexos do `Painel admin` ficam no navegador atual via `IndexedDB`
- para operacao real multiusuario, o admin definitivo deve ler do banco ou storage alimentado pelo n8n
