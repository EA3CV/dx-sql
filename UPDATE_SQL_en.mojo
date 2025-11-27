20250719

This version, available in the `test` branch, aims to introduce SQL database 
support (e.g., MariaDB, MySQL, SQLite3) to replace the current Berkeley DB and
many flat text-based files used as data storage in DXSpider.

The following data will be exported to SQL:

- /spider/local_data/user_json

- /spider/local_data/baddx
- /spider/local_data/badnode
- /spider/local_data/badspotter

- /spider/local_data/badip.global
- /spider/local_data/badip.local
- /spider/local_data/badip.torexit
- /spider/local_data/badip.torrelay

- /spider/local_data/badword.new

- /spider/filter/ann
- /spider/filter/rbn
- /spider/filter/spots
- /spider/filter/wcy
- /spider/filter/wwv

You may choose from three available backends:

- 'file'    retains DXSpider's original structure
- 'sqlite'  uses SQLite3
- 'mysql'   for MariaDB, MySQL or compatible engines

This is a reversible procedure with no data loss.

PROCEDURE TO SWITCH FROM BERKELEY DB AND TEXT FILES TO SQL BACKEND

1. This procedure does not modify or delete the original files.

2. You must have one of the supported SQL engines installed:

   sudo apt update
   sudo apt install libdbd-sqlite3-perl
   or alternatively
   sudo cpanm DBD::SQLite

3. From the console, run:

   export_user

4. Stop the cluster.

5. Modify DXVars.pm.

   After the line:

   $Internet::contest_host = "contest.dxtron.com";

   insert:

   # Backend selection
   $db_backend = 'mysql';  # 'file', 'sqlite', 'mysql'

   # MySQL/MariaDB configuration
   $mysql_admin_user = "your_root";
   $mysql_admin_pass = "your_pass";
   $mysql_db         = "dxspider";
   $mysql_user       = "your_user";
   $mysql_pass       = "your_pass";
   $mysql_host       = "127.0.0.1";

   # SQLite configuration
   $sqlite_dsn     = "dbi:SQLite:dbname=$root/local_data/dxspider.db";
   $sqlite_dbuser  = "";
   $sqlite_dbpass  = "";

6. Set the desired value for $db_backend:

   'file'     DXSpider's original flat-file backend
   'sqlite'   if using SQLite
   'mysql'    for MySQL or MariaDB

7. For MySQL/MariaDB, ensure the admin and user credentials are correct.

8. Add this line to your crontab to periodically export user data:

   # Export users.v3j database daily at 01:00
   0 1 * * * run_cmd("export_users")

9. Launch DXSpider using:

   ./cluster.pl
   to monitor the migration process.

10. If everything works as expected, stop the cluster and restart it 
    as a service.


REVERT TO THE ORIGINAL CONFIGURATION

1. From the console:

   export_user

2. Stop the cluster.

3. Edit DXVars.pm and change:

   $db_backend = 'file';

4. From terminal:

   cd /spider/local_data
   perl user_json

5. Then run from /spider/perl:

   ./convert_sql_to_files.pl

This will reconstruct the flat files and users.v3j from the SQL database.

END
