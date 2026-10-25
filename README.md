# GLDB - Generic Linux Distro Builder

GLDB (Generic Linux Distro Builder) é um projeto que automatiza a criação de uma distribuição Linux personalizada, minimalista e baseada em compilação a partir do código-fonte.

O objetivo principal é permitir montar uma base Linux enxuta, segura, leve e pronta para bootar em ISO, com kernel, BusyBox, bibliotecas e utilitários próprios.

## O que é o GLDB?

O GLDB é um script Bash que automatiza o processo de:

- baixar fontes do kernel e utilitários;
- compilar uma toolchain básica;
- montar um root filesystem (`rootfs`);
- configurar hostname, usuários, rede, teclado e boot;
- gerar uma ISO bootável com GRUB.

Em outras palavras, o projeto serve como base para criar distribuições Linux customizadas, experimentais ou educacionais.

## Para que serve?

O GLDB serve para:

- aprender como uma distribuição Linux é montada a partir das fontes;
- criar sistemas mínimos e leves para virtualização;
- montar imagens bootáveis para testes e laboratórios;
- prototipar um sistema operacional customizado;
- ter uma base de desenvolvimento para distribuições próprias.

## Requisitos

Antes de rodar o script, você precisa de:

- Linux host
- privilégios de root
- acesso à internet para baixar as fontes
- espaço suficiente em disco
- processador x86_64
- dependências de compilação instaladas

### Dependências do host

O script tenta instalar automaticamente as dependências usando `apt-get` em sistemas Debian/Ubuntu. Em geral, o ambiente precisa de pacotes como:

- build-essential
- bison
- flex
- libssl-dev
- libelf-dev
- bc
- gawk
- wget
- tar
- xz-utils
- bzip2
- xorriso
- grub-pc-bin
- grub-efi-amd64-bin
- mtools
- cpio
- pkg-config
- python3
- texinfo
- rsync
- unzip
- patch
- zlib1g-dev
- openssl
- cmake
- autoconf
- automake
- libtool

## Estrutura do projeto

```text
.
├── gldb.sh
├── README.md
├── LICENSE
├── build/
├── sources/
├── tools/
└── ...
```

## Como usar

### 1) Clone o repositório

```bash
git clone https://github.com/andersrodrig/gldb.git
cd gldb
```

### 2) Torne o script executável

```bash
chmod +x gldb.sh
```

### 3) Execute como root

```bash
sudo ./gldb.sh
```

O script vai:

1. verificar se você é root;
2. instalar dependências do host;
3. coletar as configurações da distribuição;
4. baixar as fontes do Linux e dos pacotes;
5. compilar kernel, bibliotecas e utilitários;
6. criar o root filesystem;
7. configurar o sistema inicial;
8. produzir uma ISO bootável.

### 4) Responda ao configurador

Durante a execução, ele pedirá:

- nome da distribuição;
- versão;
- hostname;
- senha do root;
- criar usuário comum;
- layout do teclado.

### 5) Aguardar a compilação

A compilação pode levar bastante tempo, dependendo da CPU, memória e rede.

Ao final, o script gera uma ISO como:

```text
DistroName_1.x.iso
```

## Características principais

- compilação do kernel Linux;
- suporte a BusyBox;
- criação de rootfs customizado;
- boot com GRUB;
- suporte a BIOS e UEFI;
- geração de ISO bootável;
- suporte a unicode e acentos no console;
- scripts para rede, áudio, teclado e instalação.

## Importante

Este projeto é um gerador de sistema Linux experimental, útil para estudo e prototipagem. Ele não é um pacote pronto para uso em produção sem revisão e validação do ambiente.

## Licença

Este projeto está licenciado sob a GNU General Public License v3.0.

Consulte o arquivo `LICENSE` para obter os termos completos.

## Autor

Anderson da Costa Rodrigues

## Contribuições

Contribuições são bem-vindas. Você pode melhorar:

- o script principal;
- a documentação;
- a geração da ISO;
- a compatibilidade com outros ambientes.

---

GLDB foi criado para facilitar a construção de distribuições Linux minimalistas e personalizadas a partir do código-fonte.
