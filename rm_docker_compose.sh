#!/bin/bash

echo "=== STOP & REMOVE OLD DOCKER COMPOSE CONTAINERS ==="
docker compose down --remove-orphans

echo ""
echo "=== REMOVE ALL EXITED / UNUSED CONTAINERS ==="
docker rm $(docker ps -aq -f status=exited) 2>/dev/null

echo ""
echo "=== REMOVE UNUSED NETWORKS ==="
docker network prune -f

echo ""
echo "=== OPTIONAL: REMOVE UNUSED VOLUMES ==="
# docker volume prune -f

echo ""
echo "=== STARTING DOCKER COMPOSE ==="
docker compose up -d

echo ""
echo "=== DONE ==="
docker ps
