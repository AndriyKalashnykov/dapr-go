#! /bin/bash

curl -i -d '{ "item": ["automobile"]}' -H "Content-type: application/json" "http://192.168.200.7:8080/orders/new"