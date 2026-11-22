# server-kit

Instala um sistema em PHP (Laravel ou PHP puro) num Ubuntu Server zerado a partir do link do GitHub.
Você escolhe a versão do PHP, de 7.4 a 8.6, e o MySQL acompanha a versão escolhida. O resto é automático.
**Um sistema por servidor.**

Installs one PHP system (Laravel or plain PHP) on a fresh Ubuntu Server from a GitHub link. Messages in Portuguese
or English.

```bash
git clone https://github.com/monill/server-kit.git
cd server-kit
sudo ./install.sh
```

Ou, sem clonar / or without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/monill/server-kit/main/install.sh | sudo bash
```

## O que ele faz

0. **Confere o servidor** antes de mexer em qualquer coisa: memória, processadores, disco, relógio, portas 80/443
   livres, acesso à internet e se o domínio já aponta para o servidor.
1. Atualiza o Ubuntu e instala o básico. Liga o firewall (só SSH, 80 e 443), o fail2ban, o swap e as atualizações
   de segurança automáticas, incluindo as do PHP e do MySQL.
2. **Baixa o sistema do GitHub.** Se o repositório for privado, mostra uma *deploy key* (chave só de leitura) para
   você colar no GitHub e espera.
3. **Descobre o tipo:** Laravel (tem `artisan`) ou PHP puro. No PHP puro, a pasta pública é `public/`,
   `public_html/`, `web/` ou `www/`, se tiver `index.php`; senão é a raiz do projeto, com os arquivos privados
   bloqueados.
4. **PHP:** sugere a versão mais nova que o projeto aceita. Para isso, lê o `composer.json` **e** o
   `composer.lock`, biblioteca por biblioteca, porque o `composer install` recusa uma versão que qualquer uma delas
   não aceite. Você pode escolher outra versão; se o projeto não aceitar, o instalador avisa antes.

   Versões sem correções de segurança (7.4, 8.0, 8.1) aparecem marcadas e pedem confirmação. Código que ainda usa as
   funções `mysql_*` do PHP 5 é recusado com uma explicação, porque não roda em nenhuma dessas versões. As extensões
   pedidas no `composer.json` (`ext-...`) são instaladas junto.
5. **MySQL** do repositório oficial da Oracle (a chave é conferida antes), sugerido pela versão do PHP:

   | PHP | MySQL sugerido |
   |---|---|
   | 7.4 – 8.1 | 8.4 LTS |
   | 8.2 ou mais novo | 9.7 LTS |

   Também dá para usar um MySQL **em outro servidor** (banco gerenciado), com certificado, ou **nenhum banco**.
   Um MySQL que já esteja no servidor é mantido.
6. **Laravel:** Redis com senha, `.env`, chave, migrations, `storage:link`, cache, agendador (cron), filas no
   Supervisor e Reverb (tempo real), se o projeto usar.
   **PHP puro:** os dados do banco ficam em `~/database.txt`, que só o usuário do sistema lê, para você copiar
   para a configuração do projeto.
7. `composer install` e `npm run build`, quando o projeto tiver.
8. **Nginx + HTTPS** com Let's Encrypt, que renova sozinho. Pedidos pelo IP ou por nomes desconhecidos são
   recusados.

O sistema roda com o **próprio usuário** do Linux, na pasta `/var/www/<nome>`, com o próprio PHP-FPM.

## Depois de instalado

O comando `server-kit` fica disponível:

```bash
sudo server-kit                    # menu
sudo server-kit update             # git pull, composer, build, migrations, reinicia filas (manutenção por segundos)
sudo server-kit update --php 8.4   # troca a versão do PHP (site, filas e agendador juntos)
sudo server-kit check              # confere o servidor e o sistema
sudo server-kit resize             # ajusta ao tamanho atual do servidor
sudo server-kit remove             # tira do ar; pergunta antes de apagar banco e arquivos
```

Rodar a instalação de novo serve para **reinstalar o mesmo sistema**: o `.env`, os dados e as senhas são mantidos.
Para colocar outro sistema no servidor, primeiro é preciso remover o atual.

## Tamanho pelo servidor

Tudo é calculado pela memória e pelos processadores. **Quando o plano da VPS aumenta, o ajuste é feito sozinho no
próximo boot**, já que mudar de plano reinicia a máquina. O `server-kit resize` faz o mesmo na hora.

| | Como calcula |
|---|---|
| PHP-FPM | 35% da memória (55% sem MySQL no servidor), ~64 MB por processo. Sem visitas, não gasta memória (`ondemand`) |
| MySQL | 25% da memória para os dados mais usados (`innodb_buffer_pool_size`) |
| Redis | 128 MB a 1 GB |
| Filas | 1 processo até 3 GB, 2 até 7 GB, depois 4 (nunca mais que os processadores) |

Exemplo com 4 GB e 2 processadores: PHP com 21 processos, MySQL com 896 MB, Redis com 256 MB e 2 filas.

## Opções

Tudo que não for passado é perguntado. Sem terminal (automação), usa as respostas sugeridas.

```
--repo URL  --branch NOME  --domain NOME  --email EMAIL  --php 7.4…8.6  --mysql 8.4|9.7  --db local|remote|none
--test      máquina de teste sem domínio: certificado próprio no lugar do Let's Encrypt
--lang pt_BR|en   --plain (perguntas simples, sem menus)   --yes (segue apesar dos avisos; nunca apaga nada)
```

```bash
sudo ./install.sh install --repo https://github.com/monill/meu-projeto --domain app.exemplo.com \
  --email eu@exemplo.com --db local
```

## Requisitos

- Ubuntu Server 22.04, 24.04 ou 26.04 LTS (x86_64 ou ARM), zerado.
- 1 GB de memória (2 GB ou mais é melhor) e 5 GB livres no disco.
- O domínio apontando para o servidor antes do HTTPS. No Cloudflare, deixe a nuvem **cinza** até terminar.

No **Ubuntu 26.04**, enquanto o repositório de versões do PHP (ondrej/php) não tiver pacotes para ele, só o PHP do
próprio Ubuntu (8.5) é oferecido. Quando o repositório for preenchido, as outras versões aparecem sozinhas.

## Testado

Em máquinas virtuais com 4 GB e 2 processadores, instalando de verdade:

| Ubuntu | Sistema | PHP | MySQL |
|---|---|---|---|
| 22.04 | Laravel 12 | 8.4 | 8.4 |
| 24.04 | Laravel 12 (reinstalação e troca 8.5 → 8.4 → 8.3) | 8.3 / 8.4 | 9.7 |
| 26.04 | PHP puro | 8.5 (do Ubuntu) | 9.7 |

## Onde fica cada coisa

| | |
|---|---|
| Sistema | `/var/www/<nome>` (usuário `<nome>`) |
| O que foi instalado (sem senhas) | `/etc/server-kit/site.conf` |
| Registro de cada execução | `/var/log/server-kit/` |
| Nginx | `/etc/nginx/sites-available/<nome>` |
| PHP-FPM | `/etc/php/<versão>/fpm/pool.d/<nome>.conf` |
| Filas e Reverb | `/etc/supervisor/conf.d/<nome>.conf` |

## Organização do código

Um `.sh` por assunto. Cada arquivo em `lib/` faz só o que o nome diz:

```
install.sh          começo: carrega lib/loader.sh
lib/loader.sh       carrega as libs, lê as opções, menu
lib/colors.sh       cores do terminal
lib/i18n.sh         mensagens no idioma escolhido (lang/pt_BR.sh, lang/en.sh)
lib/ui.sh           perguntas (menus com whiptail ou texto simples) e mensagens
lib/system.sh       conferência do servidor, pacotes base, firewall, swap, atualizações
lib/sizing.sh       contas de memória e processos
lib/state.sh        o que foi instalado
lib/php.sh          versões, o que o projeto aceita, instalação, php.ini e PHP-FPM
lib/database.sh     MySQL local ou remoto
lib/redis.sh        Redis
lib/node.sh         Node.js e npm run build
lib/composer.sh     Composer
lib/app.sh          clone, deploy key, tipo do projeto e pasta pública
lib/laravel.sh      .env, artisan, agendador
lib/nginx.sh        site e HTTPS
lib/supervisor.sh   filas e Reverb
lib/actions.sh      install, update, remove, check, resize
```

Para traduzir para outro idioma, copie `lang/en.sh` para `lang/<código>.sh` e traduza os textos.

## Licença

MIT. Veja [LICENSE](LICENSE).
