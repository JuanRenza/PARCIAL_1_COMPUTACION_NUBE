echo "----------------------------------------------------------- Actualizaciones -----------------------------------------------------------"
sudo apt-get update -y 
sudo apt-get upgrade -y
sudo apt-get install -y sshpass

echo "----------------------------------------------------------- Instalar LXD -----------------------------------------------------------"
sudo snap install lxd --channel=4.0/stable
sudo newgrp lxd

echo "Configurar el cluster"
sudo sshpass -p 'vagrant' scp vagrant@192.168.100.20:/var/snap/lxd/common/lxd/cluster.crt /home/vagrant/key.crt
sudo sed ':a;N;$!ba;s/\n/\n\n/g' /home/vagrant/key.crt
sudo touch config.yaml
sudo echo "
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
  enabled: true
  server_name: servidorWeb1
  server_address: 192.168.100.30:8443
  cluster_address: 192.168.100.20:8443
  cluster_certificate_path: /home/vagrant/key.crt 
  cluster_password: admin
  member_config:
  - entity: storage-pool
    name: servidorWeb1
    key: source
    value: """ >> config.yaml
cat config.yaml | lxd init --preseed


echo "----------------------------------------------------------- Instalar contenedor -----------------------------------------------------------"
sudo lxc init ubuntu:18.04 CTweb1 --target servidorWeb1
sudo lxc start CTweb1
sudo lxc init ubuntu:18.04 BKweb1 --target servidorWeb1
sudo lxc start BKweb1

echo "----------------------------------------------------------- Configurar el contenedor -----------------------------------------------------------"
sudo lxc exec CTweb1 -- apt update && apt upgrade
sudo lxc exec CTweb1 -- apt install apache2 -y
sudo lxc exec CTweb1 -- systemctl enable apache2
sudo lxc exec CTweb1 -- systemctl start apache2

sudo lxc exec BKweb1 -- apt update && apt upgrade
sudo lxc exec BKweb1 -- apt install apache2 -y
sudo lxc exec BKweb1 -- systemctl enable apache2
sudo lxc exec BKweb1 -- systemctl start apache2

echo "----------------------------------------------------------- Crear y cambiar archivo index -----------------------------------------------------------"
sudo touch index.html
sudo echo "
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Servicio Web 1</title>
</head>
<body>
    <h1>BIENVENIDO AL SERVICIO WEB 1</h1>
    <p>Este es el servicio web 1</p>
    <p><strong>Gracias por acceder, hasta luego</strong></p>
</body>
</html>
" >> index.html
sudo lxc file push index.html CTweb1/var/www/html/index.html

sudo touch index2.html
sudo echo "
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Backup web 1</title>
</head>
<body>
    <h1>BIENVENIDO AL SERVICIO WEB 1</h1>
    <p>Este es el servicio web 1</p>
    <p><strong>Gracias por acceder, hasta luego</strong></p>
</body>
</html>
" >> index2.html
sudo lxc file push index2.html BKweb1/var/www/html/index.html


echo "----------------------------------------------------------- Reenvio de puertos -----------------------------------------------------------"
sudo lxc config device add CTweb1 http proxy listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80
sudo lxc config device add BKweb1 http proxy listen=tcp:0.0.0.0:81 connect=tcp:127.0.0.1:80