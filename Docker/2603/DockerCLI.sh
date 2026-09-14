#!/bin/bash

docker exec -it web bash

#Clean up container 
docker rm -f db
docker run -d --name db --network app-net -e POSTGRES_PASSWORD=demo123 postgres:16-alpine
docker logs db