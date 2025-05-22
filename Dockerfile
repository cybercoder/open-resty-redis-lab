FROM openresty/openresty:alpine-fat

RUN apk add git
RUN luarocks install nginx-lua-prometheus

copy app /app
copy config/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
