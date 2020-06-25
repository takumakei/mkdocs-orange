#!/usr/bin/env bash
set -eu

ORANGE_DATA="${XDG_DATA_HOME:=$HOME/.local/share}/orange"

ORANGE_CONFIG="$ORANGE_DATA/config.json"
ORANGE_DOCO_YML="$ORANGE_DATA/docker-compose.yml"

usage() {
  cat <<EOF
usage: orange.sh <command> [<args>]

commands:
  up [--publish <port>]        start MkDocs live server
  reload                       restart MkDocs live server
  down                         stop MkDocs live server
  logs [<args>]                docker-compose logs
  config [--update]            docker-compose config
  ps [<args>]                  docker-compose ps
  doco [<args>]                docker-compose

  add [--name <name>] [dir]    add a directory
  rm name [name...]            remove directories
  ls                           list directories
  skip [--unset] <name...>     set/unset skip
EOF
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit
  fi

  local cmd="$1"
  shift
  local run="main_$cmd"
  if [[ "$(type -t "$run")" == function ]]; then
    "$run" "$@"
  else
    fatal -u "command '$cmd' not found"
  fi
}

fatal() {
  if [[ "$1" == "-u" ]]; then
    shift
    echo "error: $*" 1>&2
    usage 1>&2
  else
    echo "error: $*" 1>&2
  fi
  exit 1
}

main_config() {
  local update=
  while [[ $# -ne 0 ]]; do
    local opt="$1"
    shift
    case "$opt" in
      -u|--update)
        update=true
        ;;
      -*)
        fatal "error: unknown flag '$opt'"
        ;;
    esac
  done

  if [[ "$update" == true ]] || [[ ! -f "$ORANGE_DOCO_YML" ]]; then
    _update_doco_config
  fi
  main_doco config
}

main_up() {
  local args=()
  while [[ $# -ne 0 ]]; do
    local opt="$1"
    shift
    case "$opt" in
      -p|--publish)
        local publ="$1"
        shift
        local json="$(cat "$ORANGE_CONFIG")"
        echo "$json" | jq '.+{"publish":"'"$publ"'"}' >"$ORANGE_CONFIG"
        ;;
      *)
        args+=("$opt")
        ;;
    esac
  done
  [[ "${#args[@]}" -ne 0 ]] && set -- "${args[@]}"

  _update_doco_config
  _doco_up "$@"
}

main_down() {
  _doco_down
}

main_reload() {
  main_up -d --force-recreate --no-deps mkdocs
}

main_re() {
  main_reload "$@"
}

main_logs() {
  main_doco logs "$@"
}

main_ps() {
  main_doco ps "$@"
}

main_doco() {
  docker-compose -p orange -f "$ORANGE_DOCO_YML" "$@"
}

main_add() {
  local src="$PWD" dst=
  while [[ $# -ne 0 ]]; do
    local opt="$1"
    shift
    case "$opt" in
      -n|--name)
        dst="$1"
        shift
        ;;
      -*)
        usage
        exit 1
        ;;
      *)
        src="$opt"
        ;;
    esac
  done

  if [[ ! "$src" =~ ^/ ]]; then
    src="$PWD/$src"
  fi
  if [[ ! -d "$src" ]]; then
    fatal "error: not found '$src'"
  fi
  pushd "$src" >/dev/null
  src="$(pwd)"
  popd >/dev/null

  if [[ "$dst" == "" ]]; then
    dst="$(basename "$src")"
  fi

  local prev="$(cat "$ORANGE_CONFIG")"
  if [[ $(echo "$prev" | jq '[.targets[]|select(.dst=="'"$dst"'")]|length') -ne 0 ]]; then
    fatal "error: name already exists '$dst'"
  fi

  local next="$(echo "$prev" | jq '. + {targets: (.targets + [{src:"'"$src"'", dst:"'"$dst"'"}])}')"
  if [[ "$prev" != "$next" ]]; then
    echo "$next" >"$ORANGE_CONFIG"
    main_reload
  fi
}

main_rm() {
  if [[ $# -eq 0 ]]; then
    _main_rm "$(basename "$PWD")"
  else
    _main_rm "$@"
  fi
}

_main_rm() {
  local args="\"$1\""
  shift
  while [[ $# -ne 0 ]]; do
    args="$args,\"$1\""
    shift
  done

  local prev="$(cat "$ORANGE_CONFIG")"
  local next="$(echo "$prev" | jq '. + {targets: .targets|map(select(.dst | IN('"$args"') | not))}')"
  if [[ "$prev" != "$next" ]]; then
    echo "$next" >"$ORANGE_CONFIG"
    main_reload
  fi
}

main_ls() {
  jq -r '.targets[] | .dst + (if .skip == true then " (skip)" else "" end) + " -> " + .src' "$ORANGE_CONFIG"
}

main_skip() {
  local args=() del=
  while [[ $# -ne 0 ]]; do
    local opt="$1"
    shift
    case "$opt" in
      -u | --unset)
        del=true
        ;;
      -*)
        exit 1
        ;;
      *)
        args+=("$opt")
        ;;
    esac
  done
  [[ ${#args[@]} -eq 0 ]] && return
  set -- "${args[@]}"

  if [[ -z "$del" ]]; then
    _main_skip "$@"
  else
    _main_skip_del "$@"
  fi
}

_main_skip() {
  local args="\"$1\""
  shift
  while [[ $# -ne 0 ]]; do
    args="$args, \"$1\""
    shift
  done

  local prev="$(cat "$ORANGE_CONFIG")"
  local next="$(echo "$prev" | jq '. + {targets: .targets|map(if .dst | IN('"$args"') then . + {skip:true} else . end)}')"
  if [[ "$prev" != "$next" ]]; then
    echo "$next" >"$ORANGE_CONFIG"
    main_reload
  fi
}

_main_skip_del() {
  local args="\"$1\""
  shift
  while [[ $# -ne 0 ]]; do
    args="$args, \"$1\""
    shift
  done

  local prev="$(cat "$ORANGE_CONFIG")"
  local next="$(echo "$prev" | jq '. + {targets: .targets|map(if .dst | IN('"$args"') then del(.skip) else . end)}')"
  if [[ "$prev" != "$next" ]]; then
    echo "$next" >"$ORANGE_CONFIG"
    main_reload
  fi
}

_doco_up() {
  if [[ $# -eq 0 ]]; then
    set -- -d
  fi
  main_doco up "$@"
}

_doco_down() {
  if [[ -f "$ORANGE_DOCO_YML" ]]; then
    main_doco down -v
  fi
}

_update_doco_config() {
  _cat_doco_config >"$ORANGE_DOCO_YML"
}

_cat_doco_config() {
  local json="$(cat "$ORANGE_CONFIG")"
  local publ="$(echo "$json" | jq -r '.publish // ""')"
  if [[ -z "$publ" ]]; then
    publ="127.0.0.1:8000"
  fi
  local port="$publ"
  if [[ "$publ" =~ ^[^:]*:(.*) ]]; then
    port="${BASH_REMATCH[1]}"
  fi

  cat <<EOF
version: '3'

services:
  plantuml:
    image: plantuml/plantuml-server@sha256:8453c140841810be800904dafa994fdc0c8b705e74bdcfbd7546d47a1e1f622c
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
    image: takumakei/mkdocs-material:5.3.2
    working_dir: /work
    ports:
      - $publ:$port
    entrypoint: ["dockerize", "-wait", "http://plantuml:8080", "mkdocs"]
    command: ["serve", "-a", "0.0.0.0:$port"]
    depends_on:
      - plantuml
    volumes:
      - "$ORANGE_DATA/root:/work"
EOF
  echo "$json" | jq -r '.targets[]|select(.skip | not) | "      - " + .src + ":/work/docs/" + .dst + ":ro"'
}

main "$@"
