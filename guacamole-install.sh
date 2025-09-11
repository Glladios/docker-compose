#!/bin/bash

set -e

# Caminho de instalação
GUAC_DIR="/opt/guacamole"
mkdir -p "$GUAC_DIR"
cd "$GUAC_DIR"

echo "[1/6] Criando docker-compose.yml..."

cat > docker-compose.yml <<EOF
version: "3"

services:
  guacamole-db:
    image: mysql:5.7
    container_name: guacamole-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: guacroot
      MYSQL_DATABASE: guacamole_db
      MYSQL_USER: guacuser
      MYSQL_PASSWORD: guacpass
    volumes:
      - db_data:/var/lib/mysql

  guacd:
    image: guacamole/guacd
    container_name: guacd
    restart: unless-stopped

  guacamole:
    image: guacamole/guacamole
    container_name: guacamole
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      GUACD_HOSTNAME: guacd
      MYSQL_HOSTNAME: guacamole-db
      MYSQL_DATABASE: guacamole_db
      MYSQL_USER: guacuser
      MYSQL_PASSWORD: guacpass
    depends_on:
      - guacamole-db
      - guacd

volumes:
  db_data:
EOF

echo "[2/6] Baixando o initdb.sql..."
docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --mysql > initdb.sql

echo "[3/6] Subindo containers..."
docker-compose up -d

echo "[4/6] Aguardando o banco inicializar..."
sleep 20

echo "[5/6] Importando schema..."
docker cp initdb.sql guacamole-db:/initdb.sql
docker exec -i guacamole-db sh -c "mysql -u root -pguacroot guacamole_db < /initdb.sql"

echo "[6/6] Finalizado!"
echo
echo "✅ Apache Guacamole está no ar!"
echo "🌐 URL: http://10.32.0.34:8080/guacamole"
echo "👤 Usuário: guacadmin"
echo "🔒 Senha: guacadmin"
