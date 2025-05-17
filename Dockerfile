FROM openresty/openresty:alpine

copy app /
copy config/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf