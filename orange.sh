#!/usr/bin/env bash
set -eu
set -o pipefail

: ${ORANGE_DATA:=${XDG_DATA_HOME:=$HOME/.local/share}/orange}
: ${ORANGE_CONFIG:=$ORANGE_DATA/config.json}
: ${ORANGE_DOCO_YML:=$ORANGE_DATA/docker-compose.yml}
: ${ORANGE_TEMPLATE:=https://raw.githubusercontent.com/takumakei/mkdocs-orange/trunk/share}
: ${ORANGE_PLANTUML:=plantuml/plantuml-server:v1.2022.2}
: ${ORANGE_MKDOCS:=takumakei/mkdocs-material:8.2.8}

main() {
  if [[ $# -eq 0 ]]; then
    _usage
    return
  fi

  local cmd="$1"
  shift
  local run="_main_$cmd"
  if [[ "$(type -t "$run")" == function ]]; then
    _init
    "$run" "$@"
  else
    _error "command not found: $cmd"
  fi
}

_usage() {
  cat <<EOF
usage: orange.sh <command> [<args>]

  任意のディレクトリ群をマウントして
  lemonやorangeと同じ設定で MkDocs のライブサーバをdockerで起動する

  設定ファイル等は $ORANGE_DATA に保存する
  ライブサーバのアドレス/ポート番号は config.json で指定する

commands:
  add [--name <name>] [dir]
                       dirをnameとしてマウントする
                       dirを指定しない場合はカレントディレクトリを追加する
                       nameを指定しない場合はdirname dirの結果をnameにする
  rm name [name...]
                       nameをアンマウントする
  ls
  skip [--unset] name [name...]

  up                   docker-compose up を実行する
  reload               docker-compose down して up を実行する
  down                 docker-compose up を実行する
  config [--update]    docker-compose config を実行する
  logs                 docker-compose logs を実行する
  ps                   docker-compose ps を実行する
  doco                 docker-compose を実行する

  mkdocs [addr:]port
                       mkdocsのlistenアドレス/ポートを設定する
  plantuml [addr:]port
                       plantumlのlistenアドレス/ポートを設定する
                       コンテナの外から接続したい場合にのみ設定する
                       MkDocsコンテナはdockerのネットワークを使うので影響を受けない
EOF
}

_init() {
  for i in docker docker-compose jq curl; do
    if ! which "$i" 2>&1 >/dev/null; then
      _error "command not found: $i"
    fi
  done

  _init_file "config.json"
  _init_file "root/mkdocs.yml"
  _init_file "root/docs/README.md"
  _init_file "root/docs/assets/stylesheets/custom.print.css"
  _init_file "root/docs/assets/stylesheets/custom.style.css"
  _init_file "root/overrides/partials/footer.html"

  [[ -e "$ORANGE_DOCO_YML" ]] || _gen_doco_config >"$ORANGE_DOCO_YML"
}

# $ORANGE_DATA に指定のファイルがなければダウンロードする
_init_file() {
  local file="$1"
  local save="$ORANGE_DATA/$file"
  if [[ ! -f "$save" ]]; then
    mkdir -p "$(dirname "$save")"
    curl -o "$save" -fsSL "$ORANGE_TEMPLATE/$file"
  fi
}

# $ORANGE_CONFIG を $ORANGE_DOCO_YML に変換する
_gen_doco_config() {
  local json="$(cat "$ORANGE_CONFIG")"
  local publ="$(echo "$json" | jq -r '.publish // ""')"
  [[ ! -z "$publ" ]] || publ="127.0.0.1:8000"
  local port="$publ"
  [[ ! "$publ" =~ ^[^:]*:(.*) ]] || port="${BASH_REMATCH[1]}"

  cat <<EOF
version: '3'

services:
  plantuml:
    image: $ORANGE_PLANTUML
    restart: unless-stopped
    labels:
      io.github.takumakei.project: ornage.sh
      io.github.takumakei.project.orange.role: plantuml
EOF

  local puml="$(echo "$json" | jq -r '.plantuml // ""')"
  if [[ -n "$puml" ]]; then
    cat <<EOF
    ports:
      - $puml:8080
EOF
  fi

  cat <<EOF

  mkdocs:
    image: $ORANGE_MKDOCS
    restart: unless-stopped
    labels:
      io.github.takumakei.project: ornage.sh
      io.github.takumakei.project.orange.role: mkdocs
    working_dir: /work
    ports:
      - $publ:$port
    entrypoint: [ "dockerize", "-wait", "http://plantuml:8080", "mkdocs" ]
    command: [ "serve", "-a", "0.0.0.0:$port" ]
    depends_on:
      - plantuml
    volumes:
      - "$ORANGE_DATA/root:/work"
EOF

  echo "$json" | jq -r '.targets[]|select(.skip | not)|"      - \""+.src+":/work/docs/"+.dst+":ro\""'
}

_error() {
  echo "error: $*" >&2
  exit 1
}

_main_add() {
  local src="$PWD" dst=
  while [[ $# -ne 0 ]]; do
    local opt="$1"
    shift
    case "$opt" in
      -n | --name)
        dst="$1"
        shift
        ;;
      -*)
        _error "unknown option: $opt"
        ;;
      *)
        src="$opt"
        ;;
    esac
  done

  [[ ! "$src" =~ ^/ ]] && src="$PWD/$src"
  [[ ! -d "$src" ]] && _error "not found: $src"

  pushd "$src" >/dev/null
  src="$(pwd)"
  popd >/dev/null

  [[ "$dst" == "" ]] && dst="$(basename "$src")"

  local prev="$(cat "$ORANGE_CONFIG")"
  if [[ $(echo "$prev" | jq '[.targets[]|select(.dst=="'"$dst"'")]|length') -ne 0 ]]; then
    _error "name already exists: $dst"
  fi

  echo "$prev" | jq '. + {targets: (.targets + [{src:"'"$src"'", dst:"'"$dst"'"}])}' >"$ORANGE_CONFIG"
  _gen_doco_config >"$ORANGE_DOCO_YML"
  _main_ls
  _reload_if_up
}

_main_rm() {
  [[ $# -eq 0 ]] && set -- "$(basename "$PWD")"
  local prev="$(cat "$ORANGE_CONFIG")"
  local next="$(echo "$prev" | jq '. + {targets: .targets|map(select(.dst | IN('"$(_strjoin "$@")"') | not))}')"
  if [[ "$prev" != "$next" ]]; then
    echo "$next" >"$ORANGE_CONFIG"
    _gen_doco_config >"$ORANGE_DOCO_YML"
    _main_ls
    _reload_if_up
  else
    _error nothing changed
  fi
}

_strjoin() {
  printf -v a '"%s",' "$@"
  echo "${a%,}"
}

_main_ls() {
  jq -r '.targets[] | .dst + (if .skip == true then " (skip)" else "" end) + " -> " + .src' "$ORANGE_CONFIG"
}

# 登録は残したまま、一時的に対象外にする(しない)
_main_skip() {
  local args=() noskip=false
  while [[ $# -ne 0 ]]; do
    local opt="$1"
    shift
    case "$opt" in
      -u | --unset)
        noskip=true
        ;;
      -*)
        _error "unknown option: $opt"
        ;;
      *)
        args+=("$opt")
        ;;
    esac
  done

  [[ ${#args[@]} -eq 0 ]] && args=("$(basename "$PWD")")

  if [[ "$noskip" != true ]]; then
    _mark_skip "${args[@]}"
  else
    _mark_noskip "${args[@]}"
  fi
}

_main_noskip() {
  _main_skip --unset "$@"
}

_mark_skip() {
  local prev="$(cat "$ORANGE_CONFIG")"
  local next="$(echo "$prev" | jq '. + {targets: .targets|map(if .dst | IN('"$(_strjoin "$@")"') then . + {skip:true} else . end)}')"
  if [[ "$prev" != "$next" ]]; then
    echo "$next" >"$ORANGE_CONFIG"
    _gen_doco_config >"$ORANGE_DOCO_YML"
    _main_ls
    _reload_if_up
  else
    _error nothing changed
  fi
}

_mark_noskip() {
  local prev="$(cat "$ORANGE_CONFIG")"
  local next="$(echo "$prev" | jq '. + {targets: .targets|map(if .dst | IN('"$(_strjoin "$@")"') then del(.skip) else . end)}')"
  if [[ "$prev" != "$next" ]]; then
    echo "$next" >"$ORANGE_CONFIG"
    _gen_doco_config >"$ORANGE_DOCO_YML"
    _main_ls
    _reload_if_up
  fi
}

_reload_if_up() {
  local c="$(docker ps -q -f label=io.github.takumakei.project.orange.role=mkdocs)"
  [[ -z "$c" ]] && return
  _main_doco up -d --force-recreate --no-deps mkdocs
}

_reload_if_up_plantuml() {
  local c="$(docker ps -q -f label=io.github.takumakei.project.orange.role=plantuml)"
  [[ -z "$c" ]] && return
  _main_doco up -d --force-recreate --no-deps plantuml
}

_main_up() {
  _gen_doco_config >"$ORANGE_DOCO_YML"
  _main_doco up -d "$@"
}

_main_reload() {
  _gen_doco_config >"$ORANGE_DOCO_YML"
  _main_doco up -d plantuml
  _main_doco up -d --force-recreate --no-deps mkdocs
}

_main_down() {
  _main_doco down "$@"
}

_main_config() {
  local update=false
  for i in "$@"; do
    case "$i" in
      -u | --update)
        update=true
        ;;
      *)
        _error "unknown option: $opt"
        ;;
    esac
  done

  if [[ "$update" == true ]]; then
    _gen_doco_config >"$ORANGE_DOCO_YML"
  fi

  _main_doco config
}

_main_logs() {
  _main_doco logs "$@"
}

_main_ps() {
  _main_doco ps "$@"
}

_main_doco() {
  docker-compose -p orange -f "$ORANGE_DOCO_YML" "$@"
}

_main_mkdocs() {
  local addrport="$1"
  local prev="$(cat "$ORANGE_CONFIG")"
  local next="$(echo "$prev" | jq '.+{"publish":"'"$addrport"'"}')"
  if [[ "$prev" != "$next" ]]; then
    echo "$next" >"$ORANGE_CONFIG"
    _gen_doco_config >"$ORANGE_DOCO_YML"
    _reload_if_up
  fi
}

_main_plantuml() {
  local addrport="$1"
  local prev="$(cat "$ORANGE_CONFIG")"
  local next="$(echo "$prev" | jq '.+{"plantuml":"'"$addrport"'"}')"
  if [[ "$prev" != "$next" ]]; then
    echo "$next" >"$ORANGE_CONFIG"
    _gen_doco_config >"$ORANGE_DOCO_YML"
    _reload_if_up_plantuml
  fi
}

main "$@"
