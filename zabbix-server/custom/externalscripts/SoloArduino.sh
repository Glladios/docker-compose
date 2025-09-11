result=$(curl -s "http://$1" | head -n 1 | awk -F '|' '{print $4}' |  grep -oP '\d+\.\d+')
echo $result
