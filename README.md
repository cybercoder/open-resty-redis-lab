# open-resty-redis lab

run:
```bash
docker compose up -d
```

## set your gateway and upstream examples

```bash
docker compose exec redis redis-cli

SET gateway:mycdn.com '{"hostname": "mycdn.com", "protocol": "http", "port": "80"}'
SET gateway:mycdn.com:httproutes '[{"route": "/", "hostHeader": "example.com", "upstream": "example.com", "protocol": "http", "port": "80"}]'
```
Also can use protocol: https and port: 443
Then test the webserver:
```bash
curl -H "Host: mycdn.com" http://localhost:8080
```
