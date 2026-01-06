FROM openresty/openresty:1.27.1.2-5-alpine-slim-amd64

RUN apk --no-cache add perl libmaxminddb && ln -s /usr/lib/libmaxminddb.so.0  /usr/lib/libmaxminddb.so
RUN opm get anjia0532/lua-resty-maxminddb && \
    opm get knyar/nginx-lua-prometheus && \
    opm get fffonion/lua-resty-openssl
COPY app /app
