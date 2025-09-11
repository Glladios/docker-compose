#!/bin/bash

if [ -z "$1" ]; then
    echo "Uso: $0 <ip-ou-url>"
    exit 1
fi

URL="$1"

linha=$(wget -qO- "$URL" | head -n 1)

result=$(echo "$linha" | awk -F 'fumaca :' '{print $2}' | awk -F '|' '{print $1}' | tr -d ' ')

if [[ "$result" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    echo "$result"
else
    echo "Erro: Valor de fumaça não encontrado!" >&2
    exit 1
fi

