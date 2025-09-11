#!/bin/bash

# Script de instalação do Apache Guacamole com MariaDB
# Otimizado para VMs com 1GB RAM

set -e

echo "🚀 Instalando Apache Guacamole com MariaDB..."

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
    docker volume rm $(docker volume ls -q | grep guacamole) 2>/dev/null || true
    cd /
    rm -rf $PROJECT_DIR
fi

# Criar diretório do projeto
log "Criando diretório: $PROJECT_DIR"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Gerar senhas seguras
DB_ROOT_PASS=$(openssl rand -base64 16)
DB_USER_PASS=$(openssl rand -base64 16)

log "Senhas do banco geradas..."

# Criar docker-compose.yml otimizado para 1GB RAM
log "Criando docker-compose.yml..."
cat > docker-compose.yml << EOF
version: "3.8"
services:
  guacamole-db:
    image: mariadb:10.6
    container_name: guacamole-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: $DB_ROOT_PASS
      MYSQL_DATABASE: guacamole_db
      MYSQL_USER: guacuser
      MYSQL_PASSWORD: $DB_USER_PASS
    volumes:
      - db_data:/var/lib/mysql
      - ./initdb:/docker-entrypoint-initdb.d:ro
    mem_limit: 200m
    mem_reservation: 128m
    command: >
      --max-connections=50
      --innodb-buffer-pool-size=64M
      --innodb-log-buffer-size=8M
      --query-cache-size=0
      --query-cache-type=0
      --tmp-table-size=8M
      --max-heap-table-size=8M
      --innodb-flush-log-at-trx-commit=2
      --innodb-file-per-table=1

  guacd:
    image: guacamole/guacd:latest
    container_name: guacd
    restart: unless-stopped
    mem_limit: 100m
    mem_reservation: 64m

  guacamole:
    image: guacamole/guacamole:latest
    container_name: guacamole
    restart: unless-stopped
    ports:
      - "8082:8080"
    environment:
      GUACD_HOSTNAME: guacd
      MYSQL_HOSTNAME: guacamole-db
      MYSQL_DATABASE: guacamole_db
      MYSQL_USER: guacuser
      MYSQL_PASSWORD: $DB_USER_PASS
      CATALINA_OPTS: "-Xmx200m -Xms100m -XX:+UseSerialGC -Djava.awt.headless=true"
    depends_on:
      - guacamole-db
      - guacd
    mem_limit: 300m
    mem_reservation: 200m

volumes:
  db_data:
EOF

# Salvar credenciais
cat > credentials.txt << EOF
=== CREDENCIAIS DO GUACAMOLE ===
URL: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'):8082/guacamole
Usuario Web: guacadmin
Senha Web: guacadmin

=== BANCO DE DADOS ===
Root Password: $DB_ROOT_PASS
User: guacuser
Password: $DB_USER_PASS
Database: guacamole_db
EOF

log "Credenciais salvas em credentials.txt"

# Criar diretório para inicialização do banco
mkdir -p initdb

# Baixar schema oficial do Guacamole
log "Baixando schema do banco..."
docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --mysql > initdb/001-initdb.sql

# Baixar imagens
log "Baixando imagens Docker..."
docker pull mariadb:10.6
docker pull guacamole/guacd:latest
docker pull guacamole/guacamole:latest

# Subir containers
log "Iniciando containers..."
docker-compose up -d

# Aguardar banco inicializar
log "Aguardando banco de dados inicializar..."
sleep 30

# Verificar se banco está rodando
for i in {1..12}; do
    if docker exec guacamole-db mysqladmin ping -h localhost --silent; then
        log "Banco de dados está rodando!"
        break
    fi
    if [ $i -eq 12 ]; then
        error "Banco de dados não iniciou corretamente"
    fi
    log "Aguardando banco... ($i/12)"
    sleep 5
done

# Aguardar Guacamole inicializar
log "Aguardando Guacamole inicializar..."
sleep 20

# Verificar status final
log "Verificando containers..."
docker-compose ps

# Obter IP do servidor
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo "✅ Guacamole instalado com sucesso!"
echo ""
echo "📋 Informações de acesso:"
echo "   🌐 URL: http://$SERVER_IP:8082/guacamole"
echo "   👤 Usuário: guacadmin"
echo "   🔑 Senha: guacadmin"
echo ""
echo "📄 Credenciais salvas em: $PROJECT_DIR/credentials.txt"
echo ""
echo "🛠️  Comandos úteis:"
echo "   docker-compose logs -f           # Ver logs"
echo "   docker-compose restart           # Reiniciar"
echo "   docker stats --no-stream        # Monitor RAM"
echo ""
echo "⚠️  IMPORTANTE: Troque a senha padrão após primeiro login!"

# Mostrar uso de RAM
echo ""
echo "💾 Uso atual de memória:"
free -h
echo ""
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"

log "Instalação concluída!"
echo "🔍 Para ver as credenciais: cat $PROJECT_DIR/credentials.txt"
