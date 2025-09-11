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
}

# Verificar se Docker está instalado
if ! command -v docker &> /dev/null; then
    error "Docker não encontrado. Instale primeiro!"
    exit 1
fi

# Verificar se docker-compose está instalado
if ! command -v docker-compose &> /dev/null; then
    error "docker-compose não encontrado. Instale primeiro!"
    exit 1
fi

# Criar diretório do projeto
PROJECT_DIR="/opt/guacamole"
log "Criando diretório: $PROJECT_DIR"
sudo mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Criar docker-compose.yml
log "Criando docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: "3"
services:
  guacd:
    image: guacamole/guacd
    container_name: guacd
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 128M
        reservations:
          memory: 64M

  guacamole:
    image: guacamole/guacamole
    container_name: guacamole
    restart: unless-stopped
    ports:
      - "8082:8080"
    environment:
      GUACD_HOSTNAME: guacd
      GUACAMOLE_HOME: /guacamole
      CATALINA_OPTS: "-Xmx256m -Xms128m -XX:+UseG1GC -Djava.awt.headless=true"
    depends_on:
      - guacd
    volumes:
      - guacamole_data:/guacamole
    deploy:
      resources:
        limits:
          memory: 384M
        reservations:
          memory: 256M

volumes:
  guacamole_data:
EOF

# Baixar imagens
log "Baixando imagens Docker..."
docker-compose pull

# Criar estrutura inicial do SQLite
log "Preparando banco SQLite..."
docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --sqlite > initdb.sql

# Criar volume e banco inicial
log "Inicializando banco de dados..."
docker-compose up -d guacd
docker-compose up -d guacamole

# Aguardar containers subirem
log "Aguardando containers iniciarem..."
sleep 10

# Copiar schema para o container
docker cp initdb.sql guacamole:/tmp/initdb.sql

# Executar inicialização do banco
docker exec guacamole bash -c "
    cd /guacamole
    sqlite3 guacamole.db < /tmp/initdb.sql
"

# Reiniciar Guacamole para aplicar configurações
log "Reiniciando containers..."
docker-compose restart

# Aguardar reinicialização
sleep 15

# Verificar se está rodando
log "Verificando status dos containers..."
docker-compose ps

# Mostrar informações finais
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

echo ""
echo "✅ Instalação concluída com sucesso!"
echo ""
echo "📋 Informações de acesso:"
echo "   URL: http://$SERVER_IP:8082/guacamole"
echo "   Usuário: guacadmin"
echo "   Senha: guacadmin"
echo ""
echo "🔧 Comandos úteis:"
echo "   Ver logs: docker-compose logs -f"
echo "   Parar: docker-compose stop"
echo "   Iniciar: docker-compose start"
echo "   Reiniciar: docker-compose restart"
echo "   Status: docker-compose ps"
echo ""
echo "💾 Uso de memória:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
echo ""
echo "🚨 Importante: Troque a senha padrão após o primeiro login!"

# Limpeza
rm -f initdb.sql

log "Script finalizado!"
