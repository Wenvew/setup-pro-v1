# Instalador Rápido: Traefik v3 em Docker Swarm com Let's Encrypt

Bem-vindo\! Este é um guia para usar o script de instalação automatizada do Traefik. O objetivo é permitir que, com um único comando, você configure um servidor do zero e tenha um ambiente moderno, seguro e pronto para hospedar suas aplicações web.

Este script foi projetado para ser simples, mas por baixo dos panos ele realiza uma configuração de nível profissional.

## 🚀 O que este script faz por você?

  * **Instalação do Zero:** Prepara um servidor Ubuntu novo, instalando Docker, Docker Swarm e todas as dependências necessárias.
  * **Configuração Automática de Rede e Segurança:** Ajusta o DNS do servidor e as regras de rede para o funcionamento perfeito do Docker.
  * **Certificados SSL Automáticos (HTTPS):** Configura o Traefik para obter e renovar certificados SSL gratuitos do Let's Encrypt usando sua conta Cloudflare. Seus sites terão o cadeado de segurança automaticamente.
  * **Dashboard Seguro:** Implanta o painel de controle do Traefik, protegido por um usuário e senha que você definirá.
  * **Pronto para Escalar:** Deixa tudo preparado para que você possa adicionar seus próprios sites e serviços com facilidade.

## ✅ Pré-requisitos

Antes de começar, você precisa de três coisas. Não se preocupe, vamos detalhar cada uma\!

1.  **Um Servidor:** Um servidor "limpo" com **Ubuntu 22.04** ou superior. Pode ser de qualquer provedor de nuvem (DigitalOcean, Vultr, AWS, etc.). Você precisará do acesso `root` (ou um usuário com `sudo`).
2.  **Um Domínio:** Um nome de domínio (ex: `meudominio.com`) que você já tenha comprado.
3.  **Conta no Cloudflare e um Token de API:**
      * Seu domínio precisa estar sendo gerenciado pela Cloudflare.
      * Você precisará de um **Token de API** para permitir que o Traefik crie os registros de DNS necessários para validar seus certificados SSL.

### Como criar o Token de API da Cloudflare

Este é o passo mais importante. O token precisa de duas permissões específicas:

  * `Zone` -\> `DNS` -\> `Edit`
  * `Zone` -\> `Zone` -\> `Read`

**Passo a passo para criar o token:**

1.  Acesse o painel da Cloudflare.
2.  Vá para **My Profile** -\> **API Tokens** ou clique diretamente neste link: [Criar Token da Cloudflare](https://dash.cloudflare.com/profile/api-tokens).
3.  Clique em **"Create Token"**.
4.  Use o modelo **"Edit zone DNS"**.
5.  Em **"Zone Resources"**, selecione a zona (seu domínio) que você quer que o Traefik gerencie.
6.  Clique em **"Continue to summary"** e depois em **"Create Token"**.
7.  **Copie o token gerado\!** Esta é a única vez que ele será mostrado. Guarde-o em um local seguro.

## ⚙️ Como Usar: Passo a Passo

Com todos os pré-requisitos em mãos, o processo é muito simples.

### Passo 1: Conecte-se ao seu Servidor

Use SSH para acessar seu servidor como `root`.

```bash
ssh root@IP_DO_SEU_SERVIDOR
```

### Passo 2: Baixe o Script

Copie e cole o comando abaixo no seu terminal para baixar o script de instalação.

```bash
curl -L -o setup-provider.sh https://github.com/Wenvew/setup-pro-v1.git/main/setup-provider.sh
```


### Passo 3: Torne o Script Executável

Precisamos dar permissão para que o sistema possa executar o arquivo que baixamos.

```bash
chmod +x setup-provider.sh
```

### Passo 4: Configure Suas Variáveis

Esta é a única parte que você precisa editar. Abra o arquivo com o editor de texto `nano`.

```bash
nano setup-provider.sh
```

No topo do arquivo, você verá uma seção de configuração. Altere os valores para os seus.

**Exemplo - ANTES:**

```bash
### ======== CONFIGURE AQUI ======== ###
DOMAIN="fluxe.one"                       # seu domínio
TRAEFIK_HOST="teste-traefik.${DOMAIN}"   # host do dashboard
ACME_EMAIL="infra@fluxe.one"             # e-mail para o Let's Encrypt
DASH_USER="superadmin"                   # usuário do dashboard
### ================================= ###
```

**Exemplo - DEPOIS (com seus dados):**

```bash
### ======== CONFIGURE AQUI ======== ###
DOMAIN="meudominio.com"
TRAEFIK_HOST="painel.${DOMAIN}"
ACME_EMAIL="meuemail@gmail.com"
DASH_USER="admin"
### ================================= ###
```

Após editar, salve e saia do `nano`:

1.  Pressione `Ctrl + X`.
2.  Pressione `Y` (ou `S`) para confirmar que quer salvar.
3.  Pressione `Enter`.

### Passo 5: Execute o Script

Agora, a mágica acontece. Execute o script como `root` (ou com `sudo`).

```bash
sudo ./setup-provider.sh
```

O script começará a trabalhar. Ele vai instalar tudo, configurar a rede, o Docker e o Swarm.

### Passo 6: Interaja com o Script

O script fará duas perguntas importantes:

1.  `Cole o Cloudflare API Token:`

      * Cole aqui o token que você criou no Cloudflare e pressione `Enter`. O que você digitar não aparecerá na tela, por segurança.

2.  `Defina a senha do dashboard para o usuário 'admin':`

      * Digite uma senha forte para o seu painel do Traefik e pressione `Enter`. Novamente, a senha não aparecerá na tela.

Depois disso, o script continuará até o final. Ele fará o deploy do Traefik e executará alguns testes de verificação.

### Passo 7: Acesse seu Dashboard\!

Ao final, o script mostrará uma mensagem de sucesso com a URL do seu painel.

```
✅ Pronto. Traefik v3 + Swarm + Cloudflare DNS-01 operando em: https://painel.meudominio.com/dashboard/
```

Abra essa URL no seu navegador. Use o usuário e a senha que você definiu para fazer login.

**Parabéns\! Você tem um ambiente de hospedagem moderno e seguro funcionando\!**

## 📦 Pós-Instalação: E agora?

Seu Traefik está funcionando como um "porteiro" inteligente. Agora você precisa dizer a ele quais "portas" (serviços) ele deve abrir.

### Adicionando um Novo Site/Serviço

Para adicionar um novo serviço (por exemplo, um site, uma API, etc.), você precisa criá-lo no Docker Swarm e adicionar `labels` especiais que o Traefik entende.

**Exemplo: Adicionando um serviço simples chamado "whoami"**

1.  Crie um arquivo chamado `meu-servico.yml`:

    ```bash
    nano meu-servico.yml
    ```

2.  Cole o conteúdo abaixo, **alterando o `Host(...)` para o endereço que você quer**:

    ```yaml
    version: "3.8"

    services:
      whoami:
        image: "traefik/whoami"
        networks:
          - network_public # A mesma rede que o Traefik usa
        deploy:
          labels:
            # 1. "Liga" o Traefik para este serviço
            - "traefik.enable=true"
            
            # 2. Define a regra de roteamento (o endereço do site)
            - "traefik.http.routers.whoami.rule=Host(`info.meudominio.com`)"
            
            # 3. Diz ao Traefik para usar HTTPS e o resolvedor de certificados
            - "traefik.http.routers.whoami.entrypoints=websecure"
            - "traefik.http.routers.whoami.tls.certresolver=letsencrypt"

    networks:
      network_public:
        external: true
    ```

3.  Faça o deploy do serviço:

    ```bash
    docker stack deploy -c meu-servico.yml whoami
    ```

Aguarde um minuto, e o Traefik irá detectar o novo serviço, obter um certificado SSL para `info.meudominio.com` e começar a direcionar o tráfego para ele. Simples assim\!

### Onde os arquivos do Traefik estão?

O script armazena todos os dados importantes do Traefik em `/srv/infra/traefik/`.

  * `/srv/infra/traefik/acme/acme.json`: É aqui que seus certificados SSL são armazenados. **Faça backup deste arquivo\!**
  * `/srv/infra/traefik/logs/access.log`: Logs de acesso a todos os seus sites.

## 🛠️ Solução de Problemas

  * **O certificado não foi emitido:** Verifique se o seu Token da Cloudflare está correto e tem as permissões certas. Verifique também se o DNS do seu domínio está apontando para o IP do seu servidor.
  * **Não consigo acessar o dashboard:** Verifique se não há um firewall (no seu provedor de nuvem, por exemplo) bloqueando as portas 80 e 443.

-----