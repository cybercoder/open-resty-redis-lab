FROM golang as go-builder

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -qq --no-install-recommends \
    autoconf \
    automake \
    libtool \
    gcc \
    bash \
    make \
    git

RUN git clone https://github.com/corazawaf/libcoraza libcoraza
# RUN sed -i '/check:/ s/^/#/' libcoraza/Makefile.am
RUN cd libcoraza \
    && ./build.sh \
    && ./configure \
    && make \
    && make install

FROM openresty/openresty:buster-fat

COPY --from=go-builder /usr/local/include/coraza /usr/local/include/coraza
COPY --from=go-builder /usr/local/lib/libcoraza.a /usr/local/lib
COPY --from=go-builder /usr/local/lib/libcoraza.so /usr/local/lib

COPY nginx-lua-prometheus-0.20240525-1.rockspec /tmp/

RUN apt update && apt install -y git luarocks && \
    luarocks install /tmp/nginx-lua-prometheus-0.20240525-1.rockspec

COPY app /app
COPY config/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
