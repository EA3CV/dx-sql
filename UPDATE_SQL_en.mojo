UPDATE_SQL_en.mojo
2025-01-20

This version in the mojo branch makes use of SQL (MariaDB, MySQL,
SQLite3, etc.) so that the current Berkeley DB and most of the files
acting as plain text databases are managed by an SQL engine through
different tables.

SQL version repository:
  https://github.com/EA3CV/dx-sql   (branch: mojo)

In this version the following data are exported to SQL:

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

Three backend types are supported:

  'file'     Keeps the original DXSpider structure
  'sqlite'   Uses SQLite3
  'mysql'    For MariaDB, MySQL or similar

This procedure is fully reversible without data loss.


PROCEDURE FOR A NEW INSTALLATION
(dx-sql, mojo branch)


This procedure describes a fresh DXSpider installation using an SQL
backend from the first start.


1. Basic system dependencies

     sudo apt update
     sudo apt install git perl make gcc


2. Installing cpanminus (MANDATORY)

   Some Perl modules must be installed from CPAN.

   Recommended option:

     sudo apt install perl-app-cpanminus

   Alternatives:

     sudo apt install wget
     wget -O - https://cpanmin.us | perl - --sudo App::cpanminus

   or:

     sudo apt install curl
     curl -L https://cpanmin.us | perl - --sudo App::cpanminus


3. Recommended packages for Debian / Ubuntu

   List based on the official Dockerfile, adapted as a reference for
   Debian systems.

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


4. Perl modules installed via CPAN

   Some modules are not available or are outdated in Debian
   repositories and must be installed using cpanm:

     cpanm Curses Date::Manip
     cpanm EV Mojolicious JSON JSON::XS Data::Structure::Util
     cpanm Math::Round List::MoreUtils Date::Calc
     cpanm Net::MQTT::Simple Net::CIDR::Lite
     cpanm File::Copy::Recursive Authen::SASL
     cpanm DBI


5. SQL engine and Perl driver installation

   5.1 SQLite3 (simple option)

     sudo apt install sqlite3 libdbd-sqlite3-perl

   or alternatively:

     cpanm DBD::SQLite


   5.2 MariaDB / MySQL

     sudo apt install mariadb-server
     sudo apt install libdbd-mysql-perl

   or alternatively:

     cpanm DBD::mysql


6. Clone the dx-sql repository (mojo branch)

     cd /spider
     git clone -b mojo https://github.com/EA3CV/dx-sql.git .


7. Configure DXVars.pm

   Edit /spider/local/DXVars.pm and select the desired backend:

     $db_backend = 'sqlite';
     or
     $db_backend = 'mysql';

   Configure the parameters for the chosen backend.


8. Initialise DXSpider

     cd /spider/perl
     ./cluster.pl


9. If startup is successful, stop the cluster and start it as a
   service.

     sudo systemctl start dxspider


PROCEDURE TO SWITCH DATABASE BACKEND TO SQL
(existing DXSpider installations)


1. This procedure keeps the original files unchanged.
   The local_data directory is not modified during the update.


2. An SQL engine and the corresponding Perl driver must be installed.


3. From the DXSpider console run:

     export_user


4. Stop the DXSpider cluster completely.

     sudo systemctl stop dxspider


5. Update the code from the dx-sql repository (mojo branch)

   Only the code is updated; data and local configuration are preserved.

   5.1 Git-managed installation

     cd /spider

     cp -a local/DXVars.pm local/DXVars.pm.pre-dx-sql
     git stash push -u -m "pre-dx-sql-mojo"

     git remote set-url origin https://github.com/EA3CV/dx-sql.git
     git fetch origin
     git checkout mojo || git checkout -b mojo origin/mojo
     git pull --ff-only

     git stash pop || true
     cp -a local/DXVars.pm.pre-dx-sql local/DXVars.pm


   5.2 Non-git installation

     cd /tmp
     git clone -b mojo https://github.com/EA3CV/dx-sql.git dx-sql

     rsync -a --delete \
       --exclude '/local_data/' \
       --exclude '/local/DXVars.pm' \
       /tmp/dx-sql/ /spider/


6. Modify DXVars.pm

   Edit /spider/local/DXVars.pm and add the SQL backend configuration
   after the appropriate section.


7. Run the cluster manually to observe the migration:

     cd /spider/perl
     ./cluster.pl


REVERTING TO THE ORIGINAL CONFIGURATION


1. From the console run:

     export_user


2. Stop the cluster.

     sudo systemctl stop dxspider


3. Edit DXVars.pm and set the backend to:

     $db_backend = 'file';


4. Rebuild user_json:

     cd /spider/local_data
     perl user_json


5. Convert the SQL database back to files:

     cd /spider/perl
     ./convert_sql_to_files.pl


This rebuilds the files and users.v3j from the SQL database.

END
