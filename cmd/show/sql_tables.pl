# show/sql_tables - Show SQL table summary for DXSpider

my $self = shift;
my $line = shift;

use DBI;
use POSIX qw(strftime);

return (1, $self->msg('e5')) unless $self->priv >= 9;

my $backend = $main::db_backend;
my $dbh;

if ($backend eq 'mysql') {
	$dbh = DBI->connect(
		"DBI:mysql:database=$main::mysql_db;host=$main::mysql_host",
		$main::mysql_user, $main::mysql_pass,
		{ RaiseError => 1, AutoCommit => 1, mysql_enable_utf8mb4 => 1 }
	);
} elsif ($backend eq 'sqlite') {
	$dbh = DBI->connect(
		$main::sqlite_dsn, $main::sqlite_dbuser, $main::sqlite_dbpass,
		{ RaiseError => 1, AutoCommit => 1, sqlite_unicode => 1 }
	);
} else {
	return (0, "[ERROR] Unsupported backend: $backend");
}

sub format_time {
	my $t = shift;
	return '' unless $t;
	return strftime("%Y-%m-%d %H:%M", localtime($t)) if $t =~ /^\d+$/;
	$t =~ s/:\d{2}$//;
	return $t;
}

sub get_latest_time {
	my ($sth) = @_;
	my $val;
	if ($sth->execute) {
		($val) = $sth->fetchrow_array;
	}
	return format_time($val);
}

# BADIPS
my %badips;
my @badip_keys = qw(global local torexit torrelay);
for my $type (@badip_keys) {
	my $sth = $dbh->prepare("SELECT COUNT(*) FROM badips WHERE list_type = ?");
	$sth->execute("badip.$type");
	($badips{$type}) = $sth->fetchrow_array;
}
my $bi_last = get_latest_time($dbh->prepare("SELECT MAX(ts) FROM badips"));

# BADS
my %bads;
for my $type (qw(baddx badnode badspotter)) {
	my $sth = $dbh->prepare("SELECT COUNT(*) FROM bads WHERE list_name = ?");
	$sth->execute($type);
	($bads{$type}) = $sth->fetchrow_array;
}
my $bads_last = get_latest_time($dbh->prepare("SELECT MAX(timestamp) FROM bads"));

# BADWORDS
my $sth = $dbh->prepare("SELECT COUNT(*) FROM badwords");
$sth->execute();
my ($bw_total) = $sth->fetchrow_array;

# USERS
$sth = $dbh->prepare("SELECT COUNT(*) FROM users");
$sth->execute();
my ($user_total) = $sth->fetchrow_array;
my $users_last = get_latest_time($dbh->prepare("SELECT MAX(lastseen) FROM users"));

# FILTERS
my %filters;
for my $type (qw(ann rbn spots wcy wwv)) {
	my $sth = $dbh->prepare("SELECT COUNT(*) FROM filters WHERE sort = ?");
	$sth->execute($type);
	($filters{$type}) = $sth->fetchrow_array;
}
my $filters_last = get_latest_time($dbh->prepare("SELECT MAX(created_at) FROM filters"));

# OUTPUT
my @out;
push @out, sprintf("SQL Backend: %s", $backend);
push @out, " ";

push @out, "badips:                           bads:";
push @out, sprintf("  %-12s %5d records        %-12s %5d records", 'global',    $badips{global},    'baddx',      $bads{baddx});
push @out, sprintf("  %-12s %5d records        %-12s %5d records", 'local',     $badips{local},     'badnode',    $bads{badnode});
push @out, sprintf("  %-12s %5d records        %-12s %5d records", 'torexit',   $badips{torexit},   'badspotter', $bads{badspotter});
push @out, sprintf("  %-12s %5d records", 'torrelay', $badips{torrelay});
push @out, sprintf("Last entry: %-21s Last entry: %-19s", $bi_last, $bads_last);
push @out, " ";

push @out, sprintf("badwords       %5d records      users         %6d records", $bw_total, $user_total);
push @out, sprintf("                                  Last entry: %s", $users_last);
push @out, " ";

push @out, "filters:";
push @out, sprintf("  %-12s %5d records", $_, $filters{$_} // 0) for qw(ann rbn spots wcy wwv);
push @out, sprintf("Last entry: %s", $filters_last);
push @out, " ";

push @out, "SQL table summary completed.";
push @out, " ";

$dbh->disconnect;
return (1, @out);
