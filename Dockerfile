FROM openresty/openresty:alpine

copy app /app
copy config/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf