#!/bin/bash

if [ -z "$1" ]; then
    echo "Uso: $0 <ip-ou-url>"
    exit 1
fi

URL="$1"
linha=$(wget -qO- "$URL" | head -n 1)
result=$(echo "$linha" | awk -F 'humidadeSolo : ' '{print $2}' | awk -F '|' '{print $1}' | tr -d ' ')

# Validação mais compatível com diferentes versões do bash
if echo "$result" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
    echo "$result"
else
    echo "Erro: Valor de humidadeSolo não encontrado!" >&2
    exit 1
fi
