#
# show/lockout
#
# show all excluded users 
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my @out;

if ($line) {
	$line =~ s/[^\w\-\/]+//g;
	$line = uc($line);
}

@out = $self->spawn_cmd("show/lockout $line", sub {
	my @out;
	my @val;
	my $count = 0;

	if ($line) {
		my $u = DXUser::get($line);
		if ($u) {
			my $locked = $u->lockout // 0;
			my $status = ($locked eq '1') ? "Locked" : "Not locked";
			push @val, "$line ($status)";
			$count = 1;
		} else {
			push @val, "$line (User not found)";
		}
	} else {
		my @calls;

		if ($main::db_backend eq 'file') {
			@calls = DXUser::get_all_calls();
		} elsif ($main::db_backend eq 'mysql' || $main::db_backend eq 'sqlite') {
			require DBI;
			my $dbh;
			if ($main::db_backend eq 'mysql') {
				$dbh = DBI->connect(
					"dbi:mysql:database=$main::mysql_db;host=$main::mysql_host",
					$main::mysql_user, $main::mysql_pass,
					{ RaiseError => 1, AutoCommit => 1 }
				);
			} else {
				my $dsn  = $main::sqlite_dsn || $main::dsn;
				my $user = $main::sqlite_dbuser || "";
				my $pass = $main::sqlite_dbpass || "";
				$dbh = DBI->connect($dsn, $user, $pass, { RaiseError => 1, AutoCommit => 1 });
			}

			my $table = $main::mysql_table || 'users';
			my $sth = $dbh->prepare("SELECT `call` FROM `$table` WHERE `lockout` = '1'");
			$sth->execute();
			while (my ($call) = $sth->fetchrow_array) {
				push @calls, $call;
			}
			$dbh->disconnect;
		}

		foreach my $call (@calls) {
			my $u = DXUser::get($call);
			next unless $u;
			my $locked = $u->lockout // 0;
			if ($locked eq '1') {
				push @val, $call;
				$count++;
			}
		}
	}

	my @l;
	foreach my $entry (@val) {
		if (@l >= 5) {
			push @out, sprintf "%-14s %-14s %-14s %-14s %-14s", @l;
			@l = ();
		}
		push @l, $entry;
	}
	if (@l) {
		push @l, "" while @l < 5;
		push @out, sprintf "%-14s %-14s %-14s %-14s %-14s", @l;
	}

	push @out, "Total users listed: $count";
	return @out;
});

return (1, @out);
