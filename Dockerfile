FROM openresty/openresty:1.27.1.2-3-bookworm-fat

COPY nginx-lua-prometheus-0.20240525-1.rockspec /tmp/

RUN apt update && apt install -y git luarocks && \
    luarocks install /tmp/nginx-lua-prometheus-0.20240525-1.rockspec

COPY app /app
COPY config/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
