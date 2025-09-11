result=$(curl -s "http://$1" | head -n 1 | awk -F '|' '{print $5}' |  grep -oP '\d+\.\d+')
echo $result