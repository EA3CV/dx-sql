#
#  SQL_Utils.pm
#
#  Common utility to ensure that the database and user are available
#  at startup. Supports both MySQL and SQLite backends.
#
#  Description:
#    This module automatically checks if the configured SQL database
#    exists and is accessible. If not, it attempts to create the
#    database and user with appropriate privileges.
#
#    It is intended to be used during DXSpider initialisation when
#    the SQL backend is enabled. It relies on global variables
#    typically defined in DXVars.pm.
#
#  Public functions:
#    ensure_database_ready()   - Verifies or initialises the database
#
#  This module has no external dependencies beyond DBI and the
#  appropriate DBD driver (DBD::mysql or DBD::SQLite).
#

package SQL_Utils;

use strict;
use warnings;
use DBI;

sub ensure_database_ready {
	return if $main::db_backend eq 'file';

	if ($main::db_backend eq 'mysql') {
		_ensure_mysql_db();
	} elsif ($main::db_backend eq 'sqlite') {
		_ensure_sqlite_db();
	}
}

sub _ensure_mysql_db {
	my $db   = $main::mysql_db;
	my $user = $main::mysql_user;
	my $pass = $main::mysql_pass;
	my $host = $main::mysql_host || '127.0.0.1';

	print "[SQL_Utils] Checking access to '$db' as '$user'\@$host...\n";

	my $test_dsn = "DBI:mysql:database=$db;host=$host";
	my $test = DBI->connect($test_dsn, $user, $pass, {
		RaiseError => 0,
		PrintError => 0,
		mysql_socket => undef
	});

	if ($test) {
		print "[SQL_Utils] Access as '$user'\@$host successful. No need to create database or user.\n";
		$test->disconnect;
		return;
	}

	print "[SQL_Utils] Unable to connect as '$user'\@$host. Attempting to create database and user as admin...\n";

	my $admin_user = $main::mysql_admin_user || 'root';
	my $admin_pass = $main::mysql_admin_pass || '';

	my $admin_dsn = "DBI:mysql:information_schema;host=localhost";
	my $dbh = DBI->connect(
		$admin_dsn,
		$admin_user,
		$admin_pass,
		{ RaiseError => 1, PrintError => 0 }
	) or die "[SQL_Utils] ERROR: Cannot connect as admin '$admin_user'
";

	my $exists = $dbh->selectrow_array(
		"SELECT SCHEMA_NAME FROM SCHEMATA WHERE SCHEMA_NAME = ?",
		undef, $db
	);

	unless ($exists) {
		print "[SQL_Utils] Creating database '$db'...\n";
		$dbh->do("CREATE DATABASE `$db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
	}

	my $user_exists = $dbh->selectrow_array(
		"SELECT 1 FROM mysql.user WHERE user = ? AND host = ?",
		undef, $user, $host
	);

	unless ($user_exists) {
		print "[SQL_Utils] Creating user '$user'\@$host...\n";
		$dbh->do("CREATE USER '$user'\@'$host' IDENTIFIED BY '$pass'");
	}

	print "[SQL_Utils] Granting privileges on '$db' to '$user'\@$host...\n";
	$dbh->do("GRANT ALL PRIVILEGES ON `$db`.* TO '$user'\@'$host' IDENTIFIED BY '$pass'");
	$dbh->do("FLUSH PRIVILEGES");

	$dbh->disconnect;
	print "[SQL_Utils] MySQL database and user setup completed.\n";
}

sub _ensure_sqlite_db {
	my ($file) = $main::sqlite_dsn =~ /dbname=(.+)$/;

	unless (-e $file) {
		print "[SQL_Utils] Creating SQLite database at $file...\n";
		my $dbh = DBI->connect($main::sqlite_dsn, '', '', { RaiseError => 1 });

		if ($main::sqlite_schema_file && -f $main::sqlite_schema_file) {
			print "[SQL_Utils] Importing schema from $main::sqlite_schema_file...\n";
			open my $fh, '<', $main::sqlite_schema_file or die "Cannot open schema file: $!";
			local $/;
			my $sql = <$fh>;
			close $fh;
			$dbh->do($_) for grep { /\S/ } split(/;\s*$/, $sql);
		}

		$dbh->disconnect;
	} else {
		print "[SQL_Utils] SQLite database already exists.\n";
	}
}

1;
