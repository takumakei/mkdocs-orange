FROM squidfunk/mkdocs-material:9.5.25

RUN apk add --no-cache --virtual .devel gcc make musl-dev \
    && apk add --no-cache openssl \
    && pip install -U \
    'markdown' \
    'mdx-truly-sane-lists' \
    'git+https://github.com/kernc/mdx_unimoji' \
    'mkdocs-awesome-pages-plugin' \
    'plantuml-markdown' \
    'pymdown-extensions' \
    'python-markdown-math' \
    'mkdocs-include-markdown-plugin' \
    && apk del .devel

ENV DOCKERIZE_VERSION v0.7.0
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz
