# Cliente do TP3: curl com HTTP/3 (ngtcp2 + nghttp3) sobre OpenSSL 3.5, mais iperf3 e tc.
# Por que nao usar BoringSSL/quiche: o curl nao suporta --tls-earlydata (0-RTT) com BoringSSL.
# Requisitos (doc do curl, HTTP3.md): OpenSSL 3.5.0+ exige ngtcp2 1.12.0+.
# Se algum download falhar, ajuste os ARGs de versao. Depois de construir, confira:
#   docker run --rm --entrypoint curl tp3-client -V | grep -E "HTTP3|EarlyData"
FROM alpine:3.22 AS build
RUN apk add --no-cache build-base perl linux-headers pkgconf wget xz nghttp2-dev zlib-dev
ARG OPENSSL=3.5.0
ARG NGHTTP3=1.9.0
ARG NGTCP2=1.12.0
ARG CURL=8.14.1
ENV P=/opt/q PKG_CONFIG_PATH=/opt/q/lib/pkgconfig LDFLAGS="-Wl,-rpath,/opt/q/lib"
WORKDIR /src

RUN wget -q https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL/openssl-$OPENSSL.tar.gz \
 && tar xf openssl-$OPENSSL.tar.gz && cd openssl-$OPENSSL \
 && ./config --prefix=$P --libdir=lib && make -j"$(nproc)" >/dev/null && make install_sw >/dev/null

RUN wget -q https://github.com/ngtcp2/nghttp3/releases/download/v$NGHTTP3/nghttp3-$NGHTTP3.tar.xz \
 && tar xf nghttp3-$NGHTTP3.tar.xz && cd nghttp3-$NGHTTP3 \
 && ./configure --prefix=$P --enable-lib-only && make -j"$(nproc)" install >/dev/null

RUN wget -q https://github.com/ngtcp2/ngtcp2/releases/download/v$NGTCP2/ngtcp2-$NGTCP2.tar.xz \
 && tar xf ngtcp2-$NGTCP2.tar.xz && cd ngtcp2-$NGTCP2 \
 && ./configure --prefix=$P --enable-lib-only --with-openssl && make -j"$(nproc)" install >/dev/null

RUN wget -q https://curl.se/download/curl-$CURL.tar.xz \
 && tar xf curl-$CURL.tar.xz && cd curl-$CURL \
 && ./configure --prefix=$P --with-openssl=$P --with-ngtcp2=$P --with-nghttp3=$P --with-nghttp2 --enable-ssls-export --without-libpsl \
 && make -j"$(nproc)" install >/dev/null
# falha o build cedo se faltar HTTP/2 (E04), HTTP/3 (E05/E06) ou SSLS-EXPORT (--ssl-sessions grava o ticket TLS)
RUN /opt/q/bin/curl -V | grep -qw HTTP2 && /opt/q/bin/curl -V | grep -qw HTTP3 && /opt/q/bin/curl -V | grep -qw SSLS-EXPORT

FROM alpine:3.22
RUN apk add --no-cache iperf3 iproute2-tc ca-certificates libstdc++ libgcc bash nghttp2-libs zlib
COPY --from=build /opt/q /opt/q
ENV PATH=/opt/q/bin:$PATH
# confere no estagio final (bibliotecas resolvidas em tempo de execucao)
RUN curl -V | grep -qw HTTP2 && curl -V | grep -qw HTTP3 && curl -V | grep -qw SSLS-EXPORT
