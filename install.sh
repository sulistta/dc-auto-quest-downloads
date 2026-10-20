#!/usr/bin/env bash
# DC Auto Quest: run as the normal desktop user.
set -Eeuo pipefail

autoquest_fail() { printf 'DC Auto Quest: %s\n' "$1" >&2; exit 1; }

autoquest_platform() {
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || autoquest_fail 'este pacote requer Linux x86_64.'
    (( EUID != 0 )) || autoquest_fail 'execute como seu usuário normal, sem sudo.'
    for tool in curl tar awk sort mktemp sha256sum cp chmod mv; do
        command -v "$tool" >/dev/null || autoquest_fail "$tool não está disponível."
    done
    local process name
    for process in /proc/[0-9]*; do
        [[ -O $process && -r $process/comm ]] || continue
        IFS= read -r name <"$process/comm" || continue
        case $name in
            Discord|discord|DiscordCanary|discordcanary|DiscordPTB|discordptb)
                autoquest_fail 'feche completamente o Discord, incluindo a bandeja, e repita o comando.' ;;
        esac
    done
}

autoquest_download() {
    curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
        --retry 2 --connect-timeout 15 --max-time 180 --max-filesize "$3" --output "$2" "$1"
}

install_autoquest() (
    autoquest_platform
    local directory staged='' base archive checksum expected actual digest
    directory=$(mktemp -d "${TMPDIR:-/tmp}/dc-auto-quest-install.XXXXXXXX")
    cleanup() {
        rm -rf -- "$directory"
        [[ -z $staged ]] || rm -f -- "$staged"
        return 0
    }
    trap cleanup EXIT
    trap 'exit 130' INT TERM HUP
    base='https://github.com/sulistta/dc-auto-quest-downloads/releases/latest/download'
    archive="$directory/package.tar.gz"
    checksum="$directory/package.sha256"
    autoquest_download "$base/dc-auto-quest-linux-x64.tar.gz" "$archive" 67108864 || autoquest_fail 'não foi possível baixar o pacote Linux.'
    autoquest_download "$base/dc-auto-quest-linux-x64.tar.gz.sha256" "$checksum" 256 || autoquest_fail 'não foi possível baixar a verificação do pacote.'
    [[ $(wc -c <"$archive") -le 67108864 && $(wc -c <"$checksum") -le 256 ]] || autoquest_fail 'pacote ou verificação muito grande.'
    expected=$(<"$checksum")
    [[ $expected =~ ^([[:xdigit:]]{64})[[:blank:]]+\*?dc-auto-quest-linux-x64\.tar\.gz$ && $(wc -l <"$checksum") -le 1 ]] || autoquest_fail 'verificação do pacote inválida.'
    digest=${BASH_REMATCH[1],,}
    [[ $(sha256sum "$archive" | awk '{print $1}') == "$digest" ]] || autoquest_fail 'o SHA-256 não confere; nenhum arquivo baixado foi executado.'
    expected=$(printf '%s\n' dc-auto-quest README.md LICENSE | LC_ALL=C sort)
    actual=$(tar -tzf "$archive") || autoquest_fail 'pacote corrompido.'
    [[ $(printf '%s\n' "$actual" | LC_ALL=C sort) == "$expected" ]] || autoquest_fail 'o pacote contém arquivos ausentes, repetidos ou inesperados.'
    tar --numeric-owner -tvzf "$archive" | awk 'substr($1,1,1)!="-" || $3>33554432 || $3<1 { invalid=1 } END { exit invalid }' || autoquest_fail 'o pacote contém links ou arquivos inválidos.'
    tar -xzf "$archive" --directory "$directory" --no-same-owner --no-same-permissions
    mkdir -p -- "$HOME/.local/bin"
    staged=$(mktemp "$HOME/.local/bin/.dc-auto-quest.XXXXXXXX")
    cp -- "$directory/dc-auto-quest" "$staged"
    chmod 0700 "$staged"
    "$staged" || autoquest_fail 'a integração não foi concluída. O comando anterior foi preservado; verifique a mensagem acima e tente novamente.'
    mv -Tf -- "$staged" "$HOME/.local/bin/dc-auto-quest"
    staged=''
    printf '\nInstalação concluída. Reabra o Discord.\n'
    printf 'Status: "%s/.local/bin/dc-auto-quest" --status\nRemover: "%s/.local/bin/dc-auto-quest" --remove\n' "$HOME" "$HOME"
)

if [[ -z ${BASH_SOURCE[0]:-} || ${BASH_SOURCE[0]} == "$0" ]]; then install_autoquest; fi
