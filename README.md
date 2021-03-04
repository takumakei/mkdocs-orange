Runs MkDocs server with any directories
======================================================================

Install
----------------------------------------------------------------------

copy `orange.sh` in your $PATH.

Quick start
----------------------------------------------------------------------

1. run `orange.sh add`
1. run `orange.sh up`
1. open `localhost:8000` in your browser

Usage
----------------------------------------------------------------------

```
usage: orange.sh <command> [<args>]

  任意のディレクトリ群をマウントして
  lemonやorangeと同じ設定で MkDocs のライブサーバをdockerで起動する

  設定ファイル等は /Users/kei/.local/share/orange に保存する
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
```
