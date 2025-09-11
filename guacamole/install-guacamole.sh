#!/bin/bash

# Script de instalação do Apache Guacamole com SQLite
# Para VMs com pouca RAM (1GB)

set -e

echo "🚀 Instalando Apache Guacamole com SQLite..."

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para log
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Verificar se está rodando como root ou com sudo
if [[ $EUID -ne 0 ]]; then
    error "Execute como sudo: sudo ./install-guacamole.sh"
fi

# Verificar se Docker está instalado
if ! command -v docker &> /dev/null; then
    error "Docker não encontrado. Instale primeiro!"
fi

# Verificar se docker-compose está instalado
if ! command -v docker-compose &> /dev/null; then
    error "docker-compose não encontrado. Instale primeiro!"
fi

# Verificar se swap está ativo
if ! swapon --show | grep -q "/swapfile"; then
    warn "Swap não está ativo! Ativando..."
    swapon /swapfile || error "Falha ao ativar swap"
fi

# Limpar instalação anterior se existir
PROJECT_DIR="/opt/guacamole"
if [ -d "$PROJECT_DIR" ]; then
    log "Removendo instalação anterior..."
    cd $PROJECT_DIR
    docker-compose down --volumes 2>/dev/null || true
    docker volume rm guacamole_data 2>/dev/null || true
    cd /
    rm -rf $PROJECT_DIR
fi

# Criar diretório do projeto
log "Criando diretório: $PROJECT_DIR"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Criar docker-compose.yml otimizado
log "Criando docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: "3.8"
services:
  guacd:
    image: guacamole/guacd:latest
    container_name: guacd
    restart: unless-stopped
    mem_limit: 128m
    mem_reservation: 64m

  guacamole:
    image: guacamole/guacamole:latest
    container_name: guacamole
    restart: unless-stopped
    ports:
      - "8082:8080"
    environment:
      GUACD_HOSTNAME: guacd
      GUACAMOLE_HOME: /guacamole
      CATALINA_OPTS: "-Xmx200m -Xms100m -XX:+UseSerialGC"
    depends_on:
      - guacd
    volumes:
      - ./data:/guacamole
    mem_limit: 300m
    mem_reservation: 200m

volumes:
  guacamole_data:
EOF

# Criar diretório de dados
log "Criando estrutura de dados..."
mkdir -p data

# Baixar imagens uma por vez para não sobrecarregar a RAM
log "Baixando imagem guacd..."
docker pull guacamole/guacd:latest

log "Baixando imagem guacamole..."
docker pull guacamole/guacamole:latest

# Criar schema SQLite básico
log "Criando schema SQLite..."
cat > data/guacamole.sql << 'EOF'
-- Schema básico do Guacamole para SQLite
CREATE TABLE guacamole_entity (
    entity_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name        VARCHAR(128) NOT NULL,
    type        VARCHAR(16) NOT NULL
);

CREATE TABLE guacamole_user (
    user_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_id       INTEGER NOT NULL,
    password_hash   BLOB NOT NULL,
    password_salt   BLOB,
    password_date   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    disabled        BOOLEAN NOT NULL DEFAULT 0,
    expired         BOOLEAN NOT NULL DEFAULT 0,
    access_window_start TIME,
    access_window_end   TIME,
    valid_from      TIMESTAMP,
    valid_until     TIMESTAMP,
    timezone        VARCHAR(64),
    full_name       VARCHAR(256),
    email_address   VARCHAR(256),
    organization    VARCHAR(256),
    organizational_role VARCHAR(256)
);

CREATE TABLE guacamole_user_group (
    user_id   INTEGER NOT NULL,
    group_id  INTEGER NOT NULL,
    PRIMARY KEY (user_id, group_id)
);

CREATE TABLE guacamole_connection (
    connection_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_name     VARCHAR(128) NOT NULL,
    parent_id           INTEGER,
    protocol            VARCHAR(32) NOT NULL,
    proxy_hostname      VARCHAR(512),
    proxy_port          INTEGER,
    proxy_encryption_method VARCHAR(4),
    max_connections     INTEGER,
    max_connections_per_user INTEGER,
    connection_weight   INTEGER,
    failover_only       BOOLEAN NOT NULL DEFAULT 0
);

CREATE TABLE guacamole_connection_parameter (
    connection_id   INTEGER NOT NULL,
    parameter_name  VARCHAR(128) NOT NULL,
    parameter_value VARCHAR(4096),
    PRIMARY KEY (connection_id, parameter_name)
);

CREATE TABLE guacamole_connection_permission (
    entity_id     INTEGER NOT NULL,
    connection_id INTEGER NOT NULL,
    permission    VARCHAR(16) NOT NULL,
    PRIMARY KEY (entity_id, connection_id, permission)
);

-- Usuário admin padrão (guacadmin/guacadmin)
INSERT INTO guacamole_entity (name, type) VALUES ('guacadmin', 'USER');
INSERT INTO guacamole_user (entity_id, password_hash, password_salt) VALUES (
    1,
    X'CA458A7D494E3BE824F5E1E175A1556C0F8EEF2C2D7DF3633BEC4A29C4411960F44C4669DAD647',
    X'FE24ADC5E11E2B25288D1704ABE67A79E342ECC26064CE69C5B3177795A82264'
);
EOF

# Criar guacamole.properties
log "Criando configuração..."
cat > data/guacamole.properties << 'EOF'
# SQLite properties
sqlite-driver: org.sqlite.JDBC
sqlite-url: jdbc:sqlite:/guacamole/guacamole.db
sqlite-auto-create-accounts: true

# Basic auth
basic-user-mapping: /guacamole/user-mapping.xml
EOF

# Criar user-mapping básico
cat > data/user-mapping.xml << 'EOF'
<user-mapping>
    <!-- Usuário de exemplo -->
    <authorize username="demo" password="demo">
        <connection name="SSH Local">
            <protocol>ssh</protocol>
            <param name="hostname">localhost</param>
            <param name="port">22</param>
        </connection>
    </authorize>
</user-mapping>
EOF

# Subir containers
log "Iniciando containers..."
docker-compose up -d

# Aguardar containers
log "Aguardando containers iniciarem..."
sleep 15

# Criar banco SQLite
log "Inicializando banco de dados..."
docker exec guacamole bash -c "
    apt-get update -qq && apt-get install -y sqlite3 -qq
    cd /guacamole
    sqlite3 guacamole.db < guacamole.sql
    chown guacamole:guacamole guacamole.db
    chmod 664 guacamole.db
"

# Reiniciar guacamole para carregar o banco
log "Reiniciando Guacamole..."
docker-compose restart guacamole

# Aguardar reinicialização
sleep 10

# Verificar status
log "Verificando containers..."
docker-compose ps

# Obter IP do servidor
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo "✅ Guacamole instalado com sucesso!"
echo ""
echo "📋 Acesso:"
echo "   🌐 URL: http://$SERVER_IP:8082/guacamole"
echo "   👤 Usuário: guacadmin"
echo "   🔑 Senha: guacadmin"
echo ""
echo "🛠️  Comandos úteis:"
echo "   docker-compose logs -f    # Ver logs"
echo "   docker-compose restart    # Reiniciar"
echo "   docker stats             # Monitor RAM"
echo ""
echo "⚠️  IMPORTANTE: Troque a senha padrão!"

# Mostrar uso de RAM final
echo ""
echo "💾 Uso atual de memória:"
free -h
echo ""
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"

log "Instalação concluída!"
