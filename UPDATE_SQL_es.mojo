UPDATE_SQL_es.mojo
2025-01-20

Esta versión en la rama mojo hace uso de SQL (MariaDB, MySQL, SQLite3,
etc.) con el fin de que la actual BDD Berkeley y la mayoría de los
ficheros que actúan como BDD en texto plano pasen a ser gestionados
desde un motor SQL a través de diferentes tablas.

Repositorio de la versión SQL:
  https://github.com/EA3CV/dx-sql   (rama: mojo)

En esta versión se exporta a SQL:

  /spider/local_data/user_json

  /spider/local_data/baddx
  /spider/local_data/badnode
  /spider/local_data/badspotter

  /spider/local_data/badip.global
  /spider/local_data/badip.local
  /spider/local_data/badip.torexit
  /spider/local_data/badip.torrelay

  /spider/local_data/badword.new

  /spider/filter/ann
  /spider/filter/rbn
  /spider/filter/spots
  /spider/filter/wcy
  /spider/filter/wwv

Se permite elegir entre tres posibles backends:

  'file'     Mantiene la estructura original de DXSpider
  'sqlite'   Usa SQLite3
  'mysql'    Para MariaDB, MySQL o similar

Es un procedimiento reversible sin pérdida de datos.


PROCEDIMIENTO PARA UNA NUEVA INSTALACIÓN
(dx-sql, rama mojo)


Este procedimiento es para una instalación nueva de DXSpider utilizando
el backend SQL desde el primer arranque.


1. Dependencias básicas del sistema

     sudo apt update
     sudo apt install git perl make gcc


2. Instalación de cpanminus (OBLIGATORIO)

   Parte de los módulos Perl se instalan desde CPAN.

   Opción recomendada:

     sudo apt install perl-app-cpanminus

   Alternativas:

     sudo apt install wget
     wget -O - https://cpanmin.us | perl - --sudo App::cpanminus

   o:

     sudo apt install curl
     curl -L https://cpanmin.us | perl - --sudo App::cpanminus


3. Paquetes recomendados en Debian / Ubuntu

   Lista basada en el Dockerfile oficial, adaptada como referencia para
   sistemas Debian.

     sudo apt install \
       git openssh-client ca-certificates \
       gcc make \
       libncurses-dev \
       mariadb-client libmariadb-dev \
       perl perl-modules perl-utils \
       libdbd-mysql-perl libdb-file-perl \
       libdigest-sha-perl \
       libio-socket-ssl-perl \
       libnet-telnet-perl \
       libtimedate-perl \
       libyaml-libyaml-perl \
       libtest-simple-perl \
       libwww-perl \
       liblwp-protocol-https-perl \
       wget curl bash nano \
       libnet-smtp-ssl-perl \
       gettext libintl-perl \
       libssl-dev zlib1g-dev


4. Módulos Perl instalados vía CPAN

   Algunos módulos no están disponibles o están obsoletos en los
   repositorios Debian y deben instalarse con cpanm:

     cpanm Curses Date::Manip
     cpanm EV Mojolicious JSON JSON::XS Data::Structure::Util
     cpanm Math::Round List::MoreUtils Date::Calc
     cpanm Net::MQTT::Simple Net::CIDR::Lite
     cpanm File::Copy::Recursive Authen::SASL
     cpanm DBI


5. Instalación del motor SQL y driver Perl

   5.1 SQLite3 (opción sencilla)

     sudo apt install sqlite3 libdbd-sqlite3-perl

   o alternativamente:

     cpanm DBD::SQLite


   5.2 MariaDB / MySQL

     sudo apt install mariadb-server
     sudo apt install libdbd-mysql-perl

   o alternativamente:

     cpanm DBD::mysql


6. Clonar el repositorio dx-sql (rama mojo)

     cd /spider
     git clone -b mojo https://github.com/EA3CV/dx-sql.git .


7. Configurar DXVars.pm

   Editar /spider/local/DXVars.pm y seleccionar el backend deseado:

     $db_backend = 'sqlite';
     o
     $db_backend = 'mysql';

   Configurar los parámetros del backend elegido.


8. Inicializar DXSpider

     cd /spider/perl
     ./cluster.pl


9. Si el arranque es correcto, detener el clúster e iniciarlo como
   servicio.

     sudo systemctl start dxspider


PROCEDIMIENTO PARA CAMBIAR EL BACKEND DE BD A SQL
(instalaciones DXSpider ya clonadas)


1. Este procedimiento mantiene los ficheros originales sin cambios.
   El directorio local_data NO se modifica durante la actualización.


2. Se requiere tener instalado un motor SQL y su driver Perl.

   Opciones soportadas: SQLite3 o MariaDB/MySQL.


3. Desde la consola de DXSpider ejecutar:

     export_user


4. Parar completamente el clúster DXSpider.

     sudo systemctl stop dxspider


5. Actualizar el código desde el repositorio dx-sql (rama mojo)

   Solo se actualiza el código; los datos y la configuración local se
   conservan.

   5.1 Instalación gestionada con git

     cd /spider

     cp -a local/DXVars.pm local/DXVars.pm.pre-dx-sql
     git stash push -u -m "pre-dx-sql-mojo"

     git remote set-url origin https://github.com/EA3CV/dx-sql.git
     git fetch origin
     git checkout mojo || git checkout -b mojo origin/mojo
     git pull --ff-only

     git stash pop || true
     cp -a local/DXVars.pm.pre-dx-sql local/DXVars.pm


   5.2 Instalación sin git

     cd /tmp
     git clone -b mojo https://github.com/EA3CV/dx-sql.git dx-sql

     rsync -a --delete \
       --exclude '/local_data/' \
       --exclude '/local/DXVars.pm' \
       /tmp/dx-sql/ /spider/


6. Modificar DXVars.pm

   Editar /spider/local/DXVars.pm y, después de la línea:

     $Internet::contest_host = "contest.dxtron.com";

   añadir la configuración del backend SQL correspondiente.


7. Ejecutar el clúster manualmente para observar la migración:

     cd /spider/perl
     ./cluster.pl


VOLVER A LA CONFIGURACIÓN ORIGINAL


1. Desde la consola ejecutar:

     export_user


2. Parar el clúster.

     sudo systemctl stop dxspider


3. Editar DXVars.pm y cambiar el backend a:

     $db_backend = 'file';


4. Reconstruir user_json:

     cd /spider/local_data
     perl user_json


5. Convertir la base SQL de nuevo a ficheros:

     cd /spider/perl
     ./convert_sql_to_files.pl


Con esto se habrán reconstruido los ficheros y users.v3j a partir de la
base de datos SQL.

FIN
