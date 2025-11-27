otro:  package DXHash_SQL;

use strict;
use warnings;
use DXDebug;
use DXUtil;
use DBI;
use DXVars;
use File::Spec;
use DXClusterSync;

my $dbh;
my $table;

sub _check_db {
	return if $dbh;

	my ($dsn, $user, $pass);
	$table = 'bads';  # Fixed for both backends

	if ($main::db_backend eq 'sqlite') {
		$dsn  = $main::sqlite_dsn     or die "DXHash_SQL: \$sqlite_dsn not defined";
		$user = $main::sqlite_dbuser;
		$pass = $main::sqlite_dbpass;
	} elsif ($main::db_backend eq 'mysql') {
		$dsn  = "DBI:mysql:database=$main::mysql_db;host=$main::mysql_host";
		$user = $main::mysql_user     or die "DXHash_SQL: \$mysql_user not defined";
		$pass = $main::mysql_pass;
	} else {
		die "[DXHash_SQL] backend '$main::db_backend' not supported";
	}

	$dbh = DBI->connect($dsn, $user, $pass, {
		RaiseError => 1,
		AutoCommit => 1,
		sqlite_unicode => 1,
		mysql_enable_utf8mb4 => 1,
	}) or die "[DXHash_SQL] Error connecting to the DB: $DBI::errstr";

	my $sql = ($main::db_backend eq 'mysql')
		? "CREATE TABLE IF NOT EXISTS $table (
			   list_name VARCHAR(32) NOT NULL,
			   callsign  VARCHAR(32) NOT NULL,
			   timestamp INT NOT NULL,
			   PRIMARY KEY (list_name, callsign)
		   ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
		: "CREATE TABLE IF NOT EXISTS $table (
			   list_name TEXT NOT NULL,
			   callsign  TEXT NOT NULL,
			   timestamp INTEGER NOT NULL,
			   PRIMARY KEY (list_name, callsign)
		   )";

	dbg("[DXHash_SQL] Creating table: $table");
	$dbh->do($sql);
}

sub _sync_if_changed {
	my ($count) = @_;
	return unless $count && $count > 0;
	DXClusterSync::broadcast_load($table);
}

sub new {
	my ($pkg, $name) = @_;
	_check_db();
	my $self = bless { name => $name }, $pkg;
	$self->_import_from_file_if_needed();
	return $self;
}

sub _import_from_file_if_needed {
	my ($self) = @_;

	my $count = $dbh->selectrow_array(
		"SELECT COUNT(*) FROM $table WHERE list_name = ?",
		undef, $self->{name}
	);
	return if $count > 0;

	my $file = File::Spec->catfile($main::local_data, $self->{name});
	return unless -e $file;

	dbg("[DXHash_SQL] Importing initial data: $file");

	my $obj;
	{
		local $/;
		open my $fh, '<', $file or return;
		my $str = <$fh>;
		close $fh;
		eval { $obj = eval $str };
		if ($@ or ref($obj) ne 'DXHash') {
			dbg("DXHash_SQL: error evaluating $file: $@");
			return;
		}
	}

	my $sql = ($main::db_backend eq 'mysql')
		? "REPLACE INTO $table (list_name, callsign, timestamp) VALUES (?, ?, ?)"
		: "INSERT OR REPLACE INTO $table (list_name, callsign, timestamp) VALUES (?, ?, ?)";
	my $sth = $dbh->prepare($sql);

	my $count_imported = 0;
	for my $call (keys %$obj) {
		next if $call eq 'name';
		my $ts = $obj->{$call};
		$sth->execute($self->{name}, $call, $ts);
		$count_imported++;
	}

	dbg("[DXHash_SQL] Imported from $file: $count_imported records") if $count_imported;
}

sub put   { return; }

sub add {
	my ($self, $callsign, $timestamp) = @_;
	$callsign = uc($callsign);
	$timestamp ||= $main::systime;

	my $sth = $dbh->prepare(
		"REPLACE INTO $table (list_name, callsign, timestamp) VALUES (?, ?, ?)"
	);
	my $count = $sth->execute($self->{name}, $callsign, $timestamp);
	_sync_if_changed($count);
	return $count;
}

sub del {
	my ($self, $callsign, $exact) = @_;
	$callsign = uc($callsign);

	my @calls = ($callsign);
	unless ($exact) {
		my $base = $callsign;
		$base =~ s|(?:-\d+)?(?:/\w)?$||;
		push @calls, map { "$base-$_" } (0..99);
	}

	my $sth = $dbh->prepare("DELETE FROM $table WHERE list_name = ? AND callsign = ?");
	my $count = 0;
	for my $c (@calls) {
		$count += $sth->execute($self->{name}, $c);
	}
	_sync_if_changed($count);
	return $count;
}

sub in {
	my ($self, $callsign, $exact) = @_;
	$callsign = uc($callsign);

	my $sth = $dbh->prepare("SELECT timestamp FROM $table WHERE list_name = ? AND callsign = ?");
	$sth->execute($self->{name}, $callsign);
	return 1 if $sth->fetchrow_arrayref;

	return 0 if $exact;

	my $base = $callsign;
	$base =~ s/-\d+$//;
	$sth->execute($self->{name}, $base);
	return $sth->fetchrow_arrayref ? 1 : 0;
}

sub set {
	my ($self, $priv, $noline, $dxchan, $line) = @_;
	return (1, $dxchan->msg('e5')) unless $dxchan->priv >= $priv;
	my @f = split /\s+/, $line;
	return (1, $noline) unless @f;

	my @out;
	my $count = 0;
	for my $f (@f) {
		if ($self->in($f, 1)) {
			push @out, $dxchan->msg('hasha', uc $f, $self->{name});
			next;
		}
		$count += $self->add($f);
		push @out, $dxchan->msg('hashb', uc $f, $self->{name});
	}
	_sync_if_changed($count);
	return (1, @out);
}

sub unset {
	my ($self, $priv, $noline, $dxchan, $line) = @_;
	return (1, $dxchan->msg('e5')) unless $dxchan->priv >= $priv;
	my @f = split /\s+/, $line;
	return (1, $noline) unless @f;

	my @out;
	my $count = 0;
	for my $f (@f) {
		unless ($self->in($f, 1)) {
			push @out, $dxchan->msg('hashd', uc $f, $self->{name});
			next;
		}
		$count += $self->del($f, 1);
		push @out, $dxchan->msg('hashc', uc $f, $self->{name});
	}
	_sync_if_changed($count);
	return (1, @out);
}

sub show {
	my ($self, $priv, $dxchan) = @_;
	return (1, $dxchan->msg('e5')) unless $dxchan->priv >= $priv;

	my $sth = $dbh->prepare(
		"SELECT callsign, timestamp FROM $table WHERE list_name = ? ORDER BY callsign"
	);
	$sth->execute($self->{name});

	my @out;
	while (my ($call, $ts) = $sth->fetchrow_array) {
		push @out, $dxchan->msg('hashe', $call, cldatetime($ts));
	}

	return (1, @out);
}

sub reload {
	my ($self) = @_;

	my $type = $self->{name};  # 'baddx', 'badnode', 'badspotter'
	my $file = File::Spec->catfile($main::local_data, $type);
	return 0 unless -e $file;

	my $insert_sql = ($main::db_backend eq 'mysql')
		? "INSERT IGNORE INTO $table (list_name, callsign, timestamp) VALUES (?, ?, ?)"
		: "INSERT OR IGNORE INTO $table (list_name, callsign, timestamp) VALUES (?, ?, ?)";
	my $sth = $dbh->prepare($insert_sql);
	my $now = time;
	my $count = 0;

	open my $fh, '<', $file or return 0;
	while (<$fh>) {
		chomp;
		next unless /^\s*['"]?([\w\-\/]+)['"]?\s*=>\s*(\d+)/;
		my ($call, $ts) = (uc $1, $2);
		$sth->execute($type, $call, $ts);
		$count++;
	}
	close $fh;

	dbg("[DXHash_SQL] Reload: imported $count records into $table for type '$type'");
	#_sync_if_changed($count);
	return 1;
}

1;
