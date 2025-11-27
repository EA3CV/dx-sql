20250719

Esta versión en la rama test pretende hacer uso de SQL como MariaDB, MySQL,
SQLite3, etc., con el fin de que la actual BDD de Berkeley y la mayoría de
los ficheros que actúan como BDD en texto plano pasen a ser gestionados 
desde un motor SQL a través de diferentes tablas.

En esta versión, se exporta a SQL:

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


PROCEDIMIENTO PARA CAMBIAR EL BACKEND DE BD BERKELEY Y FICHEROS A SQL

1. Este procedimiento mantiene los ficheros originales sin cambios.

2. Se requiere tener instalado uno de estos motores SQL: MariaDB, MySQL, 
   SQLite3, ...

   sudo apt update
   sudo apt install libdbd-sqlite3-perl
   o
   sudo cpanm DBD::SQLite

3. Desde console ejecutar export_user

4. Parar el clúster.

5. Se modificará DXVars.pm

   después de esta línea:

   $Internet::contest_host = "contest.dxtron.com";

   se incluirán las siguientes líneas:

   # Backend selection
   $db_backend = 'mysql'; # 'file', 'sqlite', 'mysql'

   # MySQL/MariaDB configuration
   $mysql_admin_user = "your_root";
   $mysql_admin_pass = "your_pass";
   $mysql_db         = "dxspider";
   $mysql_user       = "your_user";
   $mysql_pass       = "your_pass";
   $mysql_host       = "127.0.0.1";

   # SQLite configuration
   $sqlite_dsn = "dbi:SQLite:dbname=$root/local_data/dxspider.db";
   $sqlite_dbuser = "";
   $sqlite_dbpass = "";

6. Se cambiará la variable $db_backend a la configuración deseada:

   'file'     Mantiene la estructura original de DXSpider
   'sqlite'   Si se desea usar SQLite
   'mysql'    Para MariaDB o MySQL

7. Se tiene que cambiar los datos de admin y user si se usa MySQL/MariaDB

8. Se aconseja incluir en el crontab la siguiente línea:

   # Export users.v3j database
   0 1 * * * run_cmd("export_users")

9. Se ejecutará ./cluster.pl para ver las trazas durante el proceso de migración.

10. Si todo ha ido bien, se puede parar el cluster e iniciarlo como servicio.

VOLVER A LA CONFIGURACIÓN ORIGINAL

1. Desde console ejecutar: 
   export_user

2. Se parará el cluster.

3. Se ha de cambiar la variable de backend:

   cd /spider/local

   en DXVars.pm se editará la línea para que ponga 'file':

   $db_backend = 'file';

4. Desde un terminal:
   cd /spider/local_data
   perl user_json

5. A continuación se ejecutará desde /spider/perl:

   ./convert_sql_to_files.pl

Con esto se habrán reconstruido los ficheros y users.v3j con los datos de la BDD SQL.

FIN
