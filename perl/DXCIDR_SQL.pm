otro:  package DXCIDR_SQL;

use strict;
use warnings;
use 5.16.1;
use DXVars;
use DXDebug;
use DBI;
use File::Spec;
use File::Basename;
use IO::File;
use DXClusterSync;

my $dbh;
my $table = 'badips';

sub _check_db {
	return if $dbh;

	my $dsn;
	my ($user, $pass);

	if ($main::db_backend eq 'sqlite') {
		$dsn  = $main::sqlite_dsn     or die "[DXCIDR_SQL] \$sqlite_dsn not defined";
		$user = $main::sqlite_dbuser;
		$pass = $main::sqlite_dbpass;
	} elsif ($main::db_backend eq 'mysql') {
		$dsn  = "DBI:mysql:database=$main::mysql_db;host=$main::mysql_host";
		$user = $main::mysql_user     or die "[DXCIDR_SQL] \$mysql_user not defined";
		$pass = $main::mysql_pass;
	} else {
		die "[DXCIDR_SQL] backend '$main::db_backend' not supported";
	}

	$dbh = DBI->connect(
		$dsn, $user, $pass,
		{
			RaiseError => 1,
			AutoCommit => 1,
			sqlite_unicode => 1,
			mysql_enable_utf8mb4 => 1,
		}
	) or die "[DXCIDR_SQL] Error connecting to the DB: $DBI::errstr";

	my $sql = ($main::db_backend eq 'mysql')
		? "CREATE TABLE IF NOT EXISTS $table (
			   ip VARCHAR(128) NOT NULL,
			   ts INT NOT NULL,
			   list_type VARCHAR(64) NOT NULL,
			   PRIMARY KEY (ip, list_type)
		   ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
		: "CREATE TABLE IF NOT EXISTS $table (
			   ip TEXT NOT NULL,
			   ts INTEGER NOT NULL,
			   list_type TEXT NOT NULL,
			   PRIMARY KEY (ip, list_type)
		   )";

	$dbh->do($sql);
}

sub _read_files {
	my @files;
	opendir(my $dir, $main::local_data) or return;
	while (my $fn = readdir $dir) {
		next unless $fn =~ /^badip\.(\w+)$/;
		push @files, File::Spec->catfile($main::local_data, $fn);
	}
	closedir $dir;
	return @files;
}

sub _import_from_files_if_needed {
	my ($self) = @_;

	my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM $table");
	return if $count && $count > 0;

	my @files = _read_files();
	return unless @files;

	my $insert_sql = ($main::db_backend eq 'mysql')
		? "INSERT IGNORE INTO $table (ip, ts, list_type) VALUES (?, ?, ?)"
		: "INSERT OR IGNORE INTO $table (ip, ts, list_type) VALUES (?, ?, ?)";
	my $sth = $dbh->prepare($insert_sql);
	my $now = time;
	my $total = 0;

	$dbh->begin_work;
	for my $file (@files) {
		my $list_type = basename($file);
		my $imported = 0;

		dbg("[DXCIDR_SQL] Importing from $list_type...");

		open my $fh, '<', $file or next;
		while (my $line = <$fh>) {
			chomp($line);
			next unless $line =~ /[\.:]/;
			next unless $line =~ /\S/;
			$sth->execute($line, $now, $list_type);
			$total++;
			$imported++;
		}
		close $fh;

		dbg("[DXCIDR_SQL] $imported IPs imported from $list_type");
	}
	$dbh->commit;

	dbg("[DXCIDR_SQL] Total $total IPs imported from files");
	#$self->_sync_if_changed($total);
}

sub new {
	_check_db();
	my $self = bless {}, shift;
	$self->_import_from_files_if_needed();
	return $self;
}

sub init {
	my ($self) = @_;
	_check_db();
	$self->_import_from_files_if_needed();
	return 1;
}

sub reload {
	my ($self) = @_;
	_check_db();

	my @files = _read_files();
	return 1 unless @files;

	my $check_sql = "SELECT 1 FROM $table WHERE ip = ? AND list_type = ?";
	my $insert_sql = "INSERT INTO $table (ip, ts, list_type) VALUES (?, ?, ?)";

	my $sth_check  = $dbh->prepare($check_sql);
	my $sth_insert = $dbh->prepare($insert_sql);
	my $now = time;
	my $total = 0;

	dbg("[DXCIDR_SQL] Reloading badip data incrementally...");
	$dbh->begin_work;

	for my $file (@files) {
		my $list_type = basename($file);
		my $imported = 0;

		open my $fh, '<', $file or next;
		while (my $line = <$fh>) {
			chomp($line);
			next unless $line =~ /[\.:]/;
			next unless $line =~ /\S/;

			$sth_check->execute($line, $list_type);
			next if $sth_check->fetchrow_array;

			$sth_insert->execute($line, $now, $list_type);
			$imported++;
			$total++;
		}
		close $fh;

		dbg("[DXCIDR_SQL] $imported new IPs loaded from $list_type");
	}

	$dbh->commit;
	dbg("[DXCIDR_SQL] Reload completed. $total new entries added.");
	#$self->_sync_if_changed($total);
	return 1;
}

sub append {
	my ($self, $suffix, @ips) = @_;
	return 0 unless $suffix;

	my $list_type = "badip.$suffix";
	my $now = time;
	my $insert_sql = ($main::db_backend eq 'mysql')
		? "INSERT IGNORE INTO $table (ip, ts, list_type) VALUES (?, ?, ?)"
		: "INSERT OR IGNORE INTO $table (ip, ts, list_type) VALUES (?, ?, ?)";
	my $sth = $dbh->prepare($insert_sql);

	my $count = 0;
	for my $ip (@ips) {
		next unless $ip =~ /[\.:]/;
		$sth->execute($ip, $now, $list_type);
		$count++;
	}
	return $count;
}

sub add {
	my ($self, @ips) = @_;
	my $count = $self->append("local", @ips);
	$self->_sync_if_changed($count);
	return $count;
}

sub remove {
	my ($self, $suffix, @ips) = @_;
	return 0 unless $suffix;
	return 0 unless @ips;

	my $list_type = "badip.$suffix";
	my $sth = $dbh->prepare("DELETE FROM $table WHERE ip = ? AND list_type = ?");

	my $count = 0;
	for my $ip (@ips) {
		next unless $ip =~ /[\.:]/;
		$sth->execute($ip, $list_type);
		$count++;
	}
	$self->_sync_if_changed($count);
	return $count;
}

sub list {
	my ($self) = @_;
	my $sth = $dbh->prepare("SELECT ip, list_type FROM $table ORDER BY list_type, ip");
	$sth->execute();
	my @out;
	while (my ($ip, $list_type) = $sth->fetchrow_array) {
		push @out, "$ip ($list_type)";
	}
	return @out;
}

sub find {
	my ($self, $ip) = @_;
	return 0 unless $ip;
	my $sth = $dbh->prepare("SELECT 1 FROM $table WHERE ip = ?");
	$sth->execute($ip);
	return $sth->fetchrow_array ? 1 : 0;
}

sub _put {
	my ($self) = @_;
	my $file = File::Spec->catfile($main::local_data, "badip.exported");
	dbg("[DXCIDR_SQL] Exporting all IPs to $file...");
	open my $fh, '>', $file or return 0;
	for my $line ($self->list) {
		print $fh "$line\n";
	}
	close $fh;
	dbg("[DXCIDR_SQL] Export completed.");
	return 1;
}

sub _sync_if_changed {
	my ($self, $count) = @_;
	return unless $count && $count > 0;
	# Note: we use 'badip' here (singular) for load command consistency
	DXClusterSync::broadcast_load('badip');
}

1;
