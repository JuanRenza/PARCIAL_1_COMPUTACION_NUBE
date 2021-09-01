#!/bin/bash
echo "----------------------------------------------------------- Actualizaciones -----------------------------------------------------------"
sudo apt-get update -y 
sudo apt-get upgrade -y

echo "----------------------------------------------------------- Instalar LXD -----------------------------------------------------------"
sudo snap install lxd --channel=4.0/stable
sudo newgrp lxd

echo "----------------------------------------------------------- Configurar el cluster -----------------------------------------------------------"
sudo  touch config.yaml
sudo  echo "
config:
  core.https_address: 192.168.100.20:8443
  core.trust_password: admin
networks:
- config:
    bridge.mode: fan
    fan.underlay_subnet: auto
  description: ""
  name: lxdfan0
  type: ""
storage_pools:
- config: {}
  description: ""
  name: local
  driver: dir
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdfan0
      type: nic
    root:
      path: /
      pool: local
      type: disk
  name: default
cluster:
  server_name: servidorHaproxy
  enabled: true
  member_config: []
  cluster_address: ""
  cluster_certificate: ""
  server_address: ""
  cluster_password: ""
  cluster_certificate_path: """ >> config.yaml
cat config.yaml | lxd init --preseed

echo "----------------------------------------------------------- Instalar contenedor -----------------------------------------------------------"
sudo lxc init ubuntu:18.04 CThaproxy --target servidorHaproxy
sudo lxc start CThaproxy

echo "----------------------------------------------------------- Actualizar el contenedor -----------------------------------------------------------"
sudo lxc exec CThaproxy -- apt update && apt upgrade

echo "----------------------------------------------------------- Instalar e iniciar Haproxy en el contenedor -----------------------------------------------------------"
sudo lxc exec CThaproxy -- apt install haproxy -y
sudo lxc exec CThaproxy -- systemctl enable haproxy
sudo lxc exec CThaproxy -- systemctl start haproxy


echo "----------------------------------------------------------- Configuración de frotend y backend en CThaproxy -----------------------------------------------------------"
sudo touch haproxy.cfg
sudo echo " 
global
	log /dev/log	local0
	log /dev/log	local1 notice
	chroot /var/lib/haproxy
	stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
	stats timeout 30s
	user haproxy
	group haproxy
	daemon

	# Default SSL material locations
	ca-base /etc/ssl/certs
	crt-base /etc/ssl/private

	# Default ciphers to use on SSL-enabled listening sockets.
	# For more information, see ciphers(1SSL). This list is from:
	#  https://hynek.me/articles/hardening-your-web-servers-ssl-ciphers/
	# An alternative list with additional directives can be obtained from
	#  https://mozilla.github.io/server-side-tls/ssl-config-generator/?server=haproxy
	ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS
	ssl-default-bind-options no-sslv3

defaults
	log	global
	mode	http
	option	httplog
	option	dontlognull
        timeout connect 4s
        timeout client  20s
        timeout server  20s
	errorfile 400 /etc/haproxy/errors/400.http
	errorfile 403 /etc/haproxy/errors/403.http
	errorfile 408 /etc/haproxy/errors/408.http
	errorfile 500 /etc/haproxy/errors/500.http
	errorfile 502 /etc/haproxy/errors/502.http
	errorfile 503 /etc/haproxy/errors/503.http
	errorfile 504 /etc/haproxy/errors/504.http


backend web-backend
  balance roundrobin
  stats enable
  stats auth admin:admin
  stats uri /haproxy?stats

  server web1 192.168.100.30:80 check inter 10s fall 3 rise 10s
  server web2 192.168.100.40:80 check inter 10s fall 3 rise 10s
  server backupweb1 192.168.100.30:81 check backup
  server backupweb2 192.168.100.40:81 check backup

frontend http
  bind *:80
  default_backend web-backend
" >> haproxy.cfg
sudo lxc file push haproxy.cfg CThaproxy/etc/haproxy/haproxy.cfg

echo "----------------------------------------------------------- Reenvio de puertos -----------------------------------------------------------"
sudo lxc config device add CThaproxy http proxy listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80

echo "----------------------------------------------------------- Crear y cambiar archivo de error -----------------------------------------------------------"
sudo touch 503.http
sudo echo "
HTTP/1.0 503 Service Unavailable
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html>
    <head>
        <title>ERROR 503</title>
    </head>
    <body>
        <h1>NO SE PUEDE ACCEDER</h1>
        <p>Todos los servidores estan caidos</p>
        <p><strong>Gracias por acceder, hasta luego</strong></p>
    </body>
</html>
" >> 503.http
sudo lxc file push 503.http CThaproxy/etc/haproxy/errors/503.http

echo "----------------------------------------------------------- Reiniciar el servicio de haproxy -----------------------------------------------------------"
sudo lxc exec CThaproxy -- systemctl restart haproxy



