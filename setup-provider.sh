#!/usr/bin/env bash
#
# Script de Provisionamento e Instalação do Traefik v3 em Docker Swarm
#
# O que faz:
# 1. Prepara um servidor Ubuntu do zero (DNS, dependências).
# 2. Instala e configura o Docker e o Docker Swarm.
# 3. Configura a rede do host para o bom funcionamento do Swarm.
# 4. Implanta o Traefik v3 configurado para usar Let's Encrypt com DNS-01 da Cloudflare.
# 5. Inclui uma série de testes e validações pós-instalação para depuração.
#
# Versão Comentada: 1.0

# --- CONFIGURAÇÃO DE SEGURANÇA DO SCRIPT ---
# -e: Encerra o script imediatamente se um comando falhar.
# -u: Encerra o script se tentar usar uma variável não definida.
# -o pipefail: Garante que um pipeline de comandos retorne o status do último comando que falhou.
set -euo pipefail

### =================================================================== ###
### ===================   CONFIGURAÇÕES PRINCIPAIS   ================== ###
### =================================================================== ###

DOMAIN="fluxe.one"                       # Seu domínio principal gerenciado pela Cloudflare.
TRAEFIK_HOST="traefik-teste.${DOMAIN}"   # O endereço completo (FQDN) para o dashboard do Traefik.
ACME_EMAIL="traefik@fluxe.one"             # E-mail para notificações do Let's Encrypt (expiração de certs).
DASH_USER="superadmin"                   # Usuário para a autenticação do dashboard.

### =================================================================== ###
### ================   INÍCIO DA AUTOMAÇÃO DO SERVIDOR   ============== ###
### =================================================================== ###

echo -e "\n==> 1. Instalando utilitários e preparando DNS do HOST"
# Garante que o sistema esteja atualizado.
apt update && apt upgrade -y
# Instala pacotes essenciais:
# - ca-certificates: Para validação de certificados SSL/TLS.
# - curl: Para transferências de dados (downloads).
# - gnupg/lsb-release: Necessários para adicionar repositórios de terceiros (como o do Docker).
# - jq: Ferramenta para processar JSON (útil para interagir com APIs).
# - bind9-dnsutils: Fornece a ferramenta 'dig' para testes de DNS.
apt install -y ca-certificates curl gnupg lsb-release jq bind9-dnsutils

# Configura o resolvedor de DNS do próprio servidor para usar o Cloudflare (1.1.1.1)
# como primário e outros como fallback. Isso garante uma resolução de DNS rápida e confiável.
# A configuração é feita de forma persistente no systemd-resolved.
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/99-cloudflare-google.conf <<'CONF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
FallbackDNS=8.8.8.8 9.9.9.9
DNSSEC=no
CONF
# Ativa e reinicia o serviço de DNS para aplicar as mudanças.
systemctl enable --now systemd-resolved
# Faz o /etc/resolv.conf apontar para o resolvedor local do systemd, a forma moderna de gerenciar DNS no Ubuntu.
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved

echo -e "\n==> Testando resolução de DNS no HOST"
# O Traefik precisa contatar a API do Let's Encrypt. Este teste confirma que o host consegue resolver o endereço.
dig +short acme-v02.api.letsencrypt.org

echo -e "\n==> 2. Instalando Docker (usando o repositório oficial)"
# Este é o método recomendado pela Docker para instalar a versão mais recente e segura.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
> /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# Garante que o Docker inicie com o sistema.
systemctl enable --now docker

echo -e "\n==> 3. Ajustando configurações do Docker (DNS, Rotação de Logs)"
# Cria o arquivo de configuração do daemon do Docker.
cat >/etc/docker/daemon.json <<'JSON'
{
  "dns": ["1.1.1.1", "1.0.0.1", "8.8.8.8"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "features": { "buildkit": true }
}
JSON
# Explicação do daemon.json:
# - "dns": Força os contêineres a usarem esses servidores DNS, evitando problemas de resolução na rede interna.
# - "log-driver/opts": Implementa a rotação de logs. Impede que os logs dos contêineres cresçam indefinidamente,
#   limitando cada arquivo a 10MB e mantendo no máximo 3 arquivos por contêiner. Essencial para a saúde do servidor.
# - "features": Ativa o BuildKit para builds de imagem mais rápidos e eficientes.
systemctl restart docker

echo -e "\n==> 4. Validando rede do host para Swarm (bridge/overlay) e ip_forward"
# Carrega o módulo de kernel necessário para a rede bridge do Docker.
modprobe br_netfilter || true
# Habilita o encaminhamento de pacotes entre diferentes interfaces de rede,
# o que é absolutamente necessário para que a rede overlay do Swarm funcione.
cat >/etc/sysctl.d/99-swarm-overlays.conf <<'EOF'
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF
# Ativa o encaminhamento de IP imediatamente e o torna persistente entre reinicializações.
sysctl -w net.ipv4.ip_forward=1
sed -i '/^net.ipv4.ip_forward/d' /etc/sysctl.conf && echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl --system >/dev/null

echo -e "\n==> 5. Inicializando o Swarm e criando a rede overlay 'network_public'"
# Detecta automaticamente o IP público do servidor para anunciar no Swarm.
PUBIP=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'); echo "PUBIP=${PUBIP}"
# Verifica se o Swarm já está ativo para não tentar inicializá-lo duas vezes (idempotência).
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]; then
  docker swarm init --advertise-addr "$PUBIP"
fi
# Verifica se a rede principal já existe antes de criá-la.
docker network inspect network_public >/dev/null 2>&1 || \
docker network create --driver overlay --attachable network_public

echo -e "\n==> 6. Criando a estrutura de pastas e permissões para o Traefik"
# O comando 'install' é uma forma robusta de criar diretórios com permissões específicas.
install -d -m 0750 /srv/infra/traefik
install -d -m 0750 /srv/infra/traefik/{acme,logs}
# A pasta de segredos é criada com permissões mais restritas (700), apenas o dono pode acessar.
install -d -m 0700 /srv/infra/traefik/.secrets

echo -e "\n==> 7. Capturando TOKEN da Cloudflare"
# Se a variável de ambiente CF_API_TOKEN não for passada para o script, ele pedirá interativamente.
if [[ -z "${CF_API_TOKEN:-}" ]]; then
  # 'read -rsp' é seguro: não exibe o que é digitado (-s) e não guarda no histórico do shell (-r).
  read -rsp "Cole o Cloudflare API Token (Zone:Read + DNS:Edit): " CF_API_TOKEN; echo
fi
# Salva o token em um arquivo, removendo quebras de linha que podem ser copiadas acidentalmente.
printf "%s" "$CF_API_TOKEN" | tr -d '\r\n' > /srv/infra/traefik/.secrets/cf_token.txt
# Define permissões restritas (apenas leitura pelo dono) para o arquivo do token.
chmod 0400 /srv/infra/traefik/.secrets/cf_token.txt
# Cria um "Docker Secret" a partir do arquivo. Secrets são a forma segura de gerenciar
# informações sensíveis no Swarm. Eles são montados em memória nos contêineres.
docker secret rm cf_token_v2 2>/dev/null || true
docker secret create cf_token_v2 /srv/infra/traefik/.secrets/cf_token.txt

### --- SUGESTÃO DE MELHORIA: Nomes de Objetos como Variáveis --- ###
# Para tornar o script mais flexível, o nome 'cf_token_v2' poderia ser uma variável.
# Exemplo:
# CF_SECRET_NAME="cloudflare_api_token"
# docker secret rm "${CF_SECRET_NAME}" 2>/dev/null || true
# docker secret create "${CF_SECRET_NAME}" /srv/infra/traefik/.secrets/cf_token.txt
# E depois usar a variável ${CF_SECRET_NAME} no arquivo YAML.
### ----------------------------------------------------------- ###

echo -e "\n==> 8. Gerando BasicAuth do dashboard"
# Se a variável DASH_PWD não for fornecida, pede interativamente.
if [[ -z "${DASH_PWD:-}" ]]; then
  read -rsp "Defina a senha do dashboard para o usuário '${DASH_USER}': " DASH_PWD; echo
fi

### --- SUGESTÃO DE MELHORIA: Geração de Senha Aleatória --- ###
# Para uma execução 100% automatizada, o script poderia gerar uma senha caso nenhuma seja fornecida.
# Descomente o bloco abaixo para habilitar este comportamento.
# if [[ -z "${DASH_PWD:-}" ]]; then
#   echo "==> Senha não definida. Gerando uma senha forte e aleatória..."
#   DASH_PWD=$(openssl rand -base64 16)
#   echo -e "\n    Usuário do Dashboard: ${DASH_USER}"
#   echo -e "    SENHA GERADA: ${DASH_PWD}\n"
# fi
### ---------------------------------------------------------- ###

# Utiliza um contêiner temporário do Apache para ter acesso ao utilitário 'htpasswd'
# sem precisar instalá-lo no host. Uma técnica limpa e eficiente.
docker run --rm httpd:2.4-alpine htpasswd -nbB "$DASH_USER" "$DASH_PWD" > /srv/infra/traefik/usersfile
# Limpa possíveis linhas em branco no arquivo gerado.
grep -v '^[[:space:]]*$' /srv/infra/traefik/usersfile | head -n1 > /srv/infra/traefik/usersfile.clean && mv /srv/infra/traefik/usersfile.clean /srv/infra/traefik/usersfile
chmod 0400 /srv/infra/traefik/usersfile

echo -e "\n==> 9. Gravando o arquivo YAML da Stack do Traefik"
# Usa um "Here Document" (cat <<'YAML') para escrever o conteúdo do arquivo de stack.
# As aspas simples em 'YAML' impedem que o shell tente substituir variáveis (como $ACME_EMAIL)
# neste momento. A substituição será feita pelo Docker no momento do deploy.
cat >/srv/infra/traefik/traefik-stack.yml <<'YAML'
version: "3.8"

services:
  traefik:
    image: traefik:3.0.4
    command:
      # Provedor Docker Swarm
      - "--providers.swarm=true"
      - "--providers.swarm.exposedbydefault=false"
      - "--providers.swarm.network=network_public"

      # Entrypoints (Portas de entrada) e Redirecionamento HTTP -> HTTPS
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"

      # Configuração do resolvedor de certificados ACME (Let's Encrypt)
      # Usando o desafio DNS-01 com o provedor Cloudflare.
      - "--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge.delaybeforecheck=0"

      # API e Dashboard
      - "--api.dashboard=true"
      - "--api.insecure=false"
      - "--log.level=INFO"

      # Configuração de logs de acesso
      - "--accesslog=true"
      - "--accesslog.format=json"
      - "--accesslog.filepath=/logs/access.log"
      - "--accesslog.fields.headers.defaultmode=drop"
      - "--accesslog.fields.headers.names.User-Agent=keep"

    ports:
      - "80:80"
      - "443:443"

    networks:
      - network_public

    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro" # :ro = Somente Leitura (mais seguro)
      - "/srv/infra/traefik/acme:/letsencrypt"
      - "/srv/infra/traefik/logs:/logs"

    secrets:
      - cf_token_v2
    environment:
      # Informa ao Traefik onde encontrar o arquivo do token dentro do contêiner.
      - CF_DNS_API_TOKEN_FILE=/run/secrets/cf_token_v2

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"

        # Roteador para o dashboard do Traefik
        - "traefik.http.routers.traefik.rule=Host(${TRAEFIK_HOST})"
        - "traefik.http.routers.traefik.entrypoints=websecure"
        - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
        - "traefik.http.routers.traefik.service=api@internal" # Roteia para a API interna do Traefik

        ### --- SUGESTÃO DE MELHORIA: Certificado Wildcard --- ###
        # Para que o Traefik gerencie certificados para *.seu-dominio.com automaticamente,
        # adicione as duas labels abaixo. Isso simplifica a adição de novos serviços.
        # - "traefik.http.routers.traefik.tls.domains[0].main=*.${DOMAIN}"
        # - "traefik.http.routers.traefik.tls.domains[0].sans=${DOMAIN}"
        ### ---------------------------------------------------- ###

        # Middleware de autenticação
        - "traefik.http.middlewares.dashboard-auth.basicauth.usersfile=/usersfile"
        - "traefik.http.routers.traefik.middlewares=dashboard-auth@docker"

    configs:
      - source: traefik_usersfile
        target: /usersfile
        mode: 0400

networks:
  network_public:
    external: true

secrets:
  cf_token_v2:
    external: true

configs:
  traefik_usersfile:
    # Em vez de um "external: true", este config é criado a partir de um arquivo local
    # no momento do deploy. Isso é útil quando o conteúdo é gerado pelo script.
    file: /srv/infra/traefik/usersfile
YAML

echo -e "\n==> 10. Exportando variáveis e fazendo o deploy"
# As variáveis precisam ser exportadas para que o comando 'docker stack deploy'
# possa encontrá-las e substituí-las no arquivo YAML.
export ACME_EMAIL TRAEFIK_HOST DOMAIN

echo "--> Validando a sintaxe do arquivo YAML..."
# 'docker compose ... config' é um ótimo comando para validar a sintaxe do arquivo
# e a substituição de variáveis antes de tentar o deploy.
docker compose -f /srv/infra/traefik/traefik-stack.yml config >/dev/null && echo "YAML OK"

echo -e "\n--> Enviando a stack para o Swarm..."
docker stack deploy -c /srv/infra/traefik/traefik-stack.yml traefik

echo -e "\n==> 11. Acompanhando logs para verificar a emissão do certificado (aguardando 30s)"
# O comando 'timeout' executa o 'docker service logs' por 30 segundos e depois o encerra.
# O 'egrep' filtra apenas as linhas mais relevantes para o processo de certificação.
timeout 30s bash -c 'docker service logs -f --since 2m traefik_traefik | egrep -i "acme|dns|certificate|error|warn" || true'

echo -e "\n==> Verificando o certificado emitido via OpenSSL"
# Conecta-se ao host via TLS e extrai informações do certificado, como a entidade emissora e as datas.
openssl s_client -connect "${TRAEFIK_HOST}:443" -servername "${TRAEFIK_HOST}" </dev/null 2>/dev/null \
 | openssl x509 -noout -issuer -subject -dates || true

echo -e "\n==> Verificando arquivos dentro do contêiner do Traefik"
# Pega o ID do contêiner do Traefik e executa comandos dentro dele para confirmar
# que o secret do token e o arquivo acme.json foram montados corretamente.
CID=$(docker ps --filter "name=traefik_traefik" -q | head -n1)
if [[ -n "$CID" ]]; then
  docker exec -it "$CID" sh -lc 'echo -n "Tamanho do secret do token: "; wc -c < /run/secrets/cf_token_v2; echo "Status do acme.json:"; ls -lh /letsencrypt/acme.json'
fi

echo -e "\n==> Testando acesso HTTP/HTTPS e autenticação"
# Usa 'curl' para simular o acesso de um navegador e verificar os códigos de resposta.
echo "--> Testando redirecionamento HTTP (espera 301/308)"
curl -I "http://${TRAEFIK_HOST}" || true
echo "--> Testando acesso HTTPS sem autenticação (espera 401 Unauthorized)"
curl -I "https://${TRAEFIK_HOST}/dashboard/" || true
echo "--> Testando acesso HTTPS com autenticação (espera 200 OK)"
# O '-s' silencia o output, e o 'head' mostra apenas as primeiras linhas da resposta HTML.
curl -s -u "${DASH_USER}:${DASH_PWD}" "https://{TRAEFIK_HOST}/dashboard/" | head -n 3 || true

echo -e "\n==> Verificando as últimas linhas do log de acesso"
tail -n 5 /srv/infra/traefik/logs/access.log || true

echo -e "\n✅ Pronto. Traefik v3 + Swarm + Cloudflare DNS-01 operando em: https://${TRAEFIK_HOST}/dashboard/"