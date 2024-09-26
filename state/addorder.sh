#! /bin/bash

ORDERID=$(curl -s -d '{ "item": ["automobile"]}' -H "Content-type: application/json" "http://192.168.200.7:8080/orders/new"| jq -r '.order')
echo "Created order: $ORDERID"
# expected output: {"order":"order-5ee1f788", "status":"received"}
# echo {\"order\":\"order-5ee1f788\", \"status\":\"received\"} | jq -r '.order'

echo "Fetched order: $ORDERID"
curl -s  -H "Content-type: application/json" "http://192.168.200.7:8080/orders/order/$ORDERID"
echo ""