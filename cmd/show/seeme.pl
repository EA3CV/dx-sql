#
# show/registered
#
# show all registered users 
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
#

# List users with rbnseeme == 1
# If priv < 2   Only own
# If priv >= 2  One call or all can be consulted

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 1;

my @out;

if ($line) {
	$line =~ s/[^\w\-\/]+//g;
	$line = uc($line);
}

@out = $self->spawn_cmd("show/seeme $line", sub {
	my @val;
	my $count = 0;
	my %call;

	# Permisos
	if ($self->priv < 2) {
		$call{ $self->{call} } = 1;
	} elsif ($line) {
		$call{$line} = 1 unless $line eq 'ALL';
	} else {
		# Search all users with rbnseeme == '1'.
		if ($main::db_backend eq 'file') {
			for (my ($action, $key, $data) = (DXUser::R_FIRST, undef, undef);
				 !$DXUser::dbm->seq($key, $data, $action);
				 $action = DXUser::R_NEXT) {
				my $u = DXUser::get($key);
				next unless $u;
				$call{$key} = 1 if $u->rbnseeme && $u->rbnseeme eq '1';
			}
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
			my $sth = $dbh->prepare("SELECT `call` FROM `$table` WHERE `rbnseeme` = '1'");
			$sth->execute();
			while (my ($c) = $sth->fetchrow_array) {
				$call{$c} = 1;
			}
			$dbh->disconnect;
		}
	}

	foreach my $key (sort keys %call) {
		my $u = eval { DXUser::get($key) };
		next unless $u;
		my $r = $u->rbnseeme;
		next unless defined $r && $r eq '1';
		my $o = DXChannel::get($key);
		push @val, $key . ($o ? '+' : '');
		++$count;
	}

	my @out;
	my @l;
	push @out, "RBN See Me Users (active)";
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

	push @out, $self->msg('rec', $count);
	return @out;
});

return (1, @out);
