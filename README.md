# open-resty-redis lab

run:
```bash
docker compose up -d
```

## set your gateway and upstream examples

```bash
docker compose exec redis redis-cli

SET example.com '{"fullchain": "string", "privkey": "string", "port": 80, "protocol": "http", "namespace": "string", "gateway":"string"}'
SET httproute:example.com:/ '{"lb_method": "rr", "upstreams": [{"host_header":"example.com","protocol":"https","server":"example.com","port":443, "weight":"1"}]}'
```
Also can use protocol: https and port: 443
Then test the webserver:
```bash
curl -H "Host: mycdn.com" http://localhost:8080
```
