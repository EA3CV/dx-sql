#
# show/groups
#
# Show all unique group names used by users
#
# Compatible with file, mysql, sqlite backends
#

use JSON;

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 1;

my @out;

@out = $self->spawn_cmd("show/groups", sub {
	my @out;
	my %groups;
	my $count = 0;

	if ($main::db_backend eq 'file') {
		my @calls = DXUser::get_all_calls();
		foreach my $call (@calls) {
			my $u = DXUser::get($call);
			next unless $u;
			my $group_field = $u->group;
			next unless $group_field;

			my $glist;
			eval { $glist = decode_json($group_field) };
			next if $@ || ref($glist) ne 'ARRAY';

			foreach my $g (@$glist) {
				next unless $g && $g =~ /\w/;
				$groups{$g}++;
			}
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
		my $sth = $dbh->prepare("SELECT `group` FROM `$table` WHERE `group` IS NOT NULL AND `group` != ''");
		$sth->execute();
		while (my ($group_json) = $sth->fetchrow_array) {
			my $glist;
			eval { $glist = decode_json($group_json) };
			next if $@ || ref($glist) ne 'ARRAY';

			foreach my $g (@$glist) {
				next unless $g && $g =~ /\w/;
				$groups{$g}++;
			}
		}
		$dbh->disconnect;
	}

	my @all = sort keys %groups;
	my @line;
	foreach my $g (@all) {
		if (@line >= 5) {
			push @out, sprintf "%-14s %-14s %-14s %-14s %-14s", @line;
			@line = ();
		}
		push @line, $g;
	}
	if (@line) {
		push @line, "" while @line < 5;
		push @out, sprintf "%-14s %-14s %-14s %-14s %-14s", @line;
	}

	push @out, "Total groups: " . scalar(@all);
	return @out;
});

return (1, @out);
