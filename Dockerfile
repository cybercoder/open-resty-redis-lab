FROM openresty/openresty:alpine-fat

RUN apk add git
# RUN luarocks install nginx-lua-prometheus
COPY nginx-lua-prometheus-0.20240525-1.rockspec /tmp/
RUN luarocks install /tmp/nginx-lua-prometheus-0.20240525-1.rockspec

copy app /app
copy config/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
