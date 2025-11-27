package BadWords_SQL;

use strict;
use warnings;
use DBI;
use DXVars;
use DXUtil;
use DXDebug;
use IO::File;
use File::Spec;
use DXClusterSync;

sub new {
	my ($class) = @_;
	my $self = {};
	bless $self, $class;

	$self->{table} = 'badwords';

	my $dsn;
	my ($user, $pass);

	if ($main::db_backend eq 'sqlite') {
		$dsn  = $main::sqlite_dsn     or die "[BadWords_SQL] \$sqlite_dsn not defined";
		$user = $main::sqlite_dbuser;
		$pass = $main::sqlite_dbpass;
	} elsif ($main::db_backend eq 'mysql') {
		$dsn  = "DBI:mysql:database=$main::mysql_db;host=$main::mysql_host";
		$user = $main::mysql_user     or die "[BadWords_SQL] \$mysql_user not defined";
		$pass = $main::mysql_pass;
	} else {
		die "[BadWords_SQL] Backend '$main::db_backend' not supported";
	}

	$self->{dbh} = DBI->connect($dsn, $user, $pass, {
		RaiseError => 1,
		AutoCommit => 1,
		sqlite_unicode => 1,
		mysql_enable_utf8mb4 => 1
	}) or die "[BadWords_SQL] Error connecting to DB: $DBI::errstr";

	$self->_create_table_if_needed();
	$self->_populate_if_empty();

	return $self;
}

sub _create_table_if_needed {
	my ($self) = @_;
	my $sql = ($main::db_backend eq 'mysql')
		? "CREATE TABLE IF NOT EXISTS `$self->{table}` (
				`word` VARCHAR(64) NOT NULL PRIMARY KEY
			) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
		: "CREATE TABLE IF NOT EXISTS `$self->{table}` (
				`word` TEXT PRIMARY KEY
			)";

	$self->{dbh}->do($sql);
}

sub _populate_if_empty {
	my ($self) = @_;
	my $dbh = $self->{dbh};
	my $table = $self->{table};

	my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM $table");
	return if $count > 0;

	my %palabras;
	my $base_dir = $main::local_data;

	my $newfile = File::Spec->catfile($base_dir, 'badword.new');
	if (-e $newfile) {
		my $fh = IO::File->new($newfile);
		while (<$fh>) {
			chomp;
			next if /^\s*#/;
			my ($w, undef) = _process_word($_);
			$palabras{$w} = 1 if $w;
		}
		$fh->close;
	} else {
		my $bw_file = File::Spec->catfile($base_dir, 'badword');
		if (-e $bw_file) {
			my $fh = IO::File->new($bw_file);
			while (<$fh>) {
				chomp;
				next if /^\s*#/;
				if (/^(\w+)\s+=>\s+\d+,/) {
					my ($w, undef) = _process_word($1);
					$palabras{$w} = 1 if $w;
				}
			}
			$fh->close;
		}

		my $regex_file = File::Spec->catfile($base_dir, 'badw_regex');
		if (-e $regex_file) {
			my $fh = IO::File->new($regex_file);
			while (<$fh>) {
				chomp;
				next if /^\s*#/;
				for my $raw (split /\s+/, uc $_) {
					my ($w, undef) = _process_word($raw);
					$palabras{$w} = 1 if $w;
				}
			}
			$fh->close;
		}
	}

	my $insert_sql = ($main::db_backend eq 'mysql')
		? "INSERT IGNORE INTO $table (word) VALUES (?)"
		: "INSERT OR IGNORE INTO $table (word) VALUES (?)";

	my $sth = $dbh->prepare($insert_sql);
	my $inserted = 0;
	for my $w (sort keys %palabras) {
		$sth->execute($w);
		$inserted++;
	}

	dbg("[BadWords_SQL] Table '$table' initialised with $inserted words");
}

sub load_into {
	my ($self, $in_ref, $relist_ref) = @_;
	my $sth = $self->{dbh}->prepare("SELECT word FROM $self->{table}");
	$sth->execute;

	my %seen;
	while (my ($word) = $sth->fetchrow_array) {
		my ($cleaned, $regex) = _process_word($word);
		next unless $cleaned && !$seen{$cleaned}++;
		$in_ref->{$cleaned} = $regex;
		push @$relist_ref, [ $cleaned, $regex ];
		dbg("[BadWords_SQL] Loading $cleaned = $regex") if isdbg('badword');
	}
}

sub put {
	return;
}

sub add_regex {
	my ($self, $input) = @_;
	my @list = split /\s+/, $input;
	my @out;

	my $sql = ($main::db_backend eq 'mysql')
		? "INSERT IGNORE INTO $self->{table} (word) VALUES (?)"
		: "INSERT OR IGNORE INTO $self->{table} (word) VALUES (?)";

	my $sth = $self->{dbh}->prepare($sql);

	foreach my $entry (@list) {
		my ($w, $regex) = _process_word($entry);
		next unless $w;
		$sth->execute($w);
		push @out, $w;
	}

	$self->_sync_if_changed(scalar @out);
	return @out;
}

sub del_regex {
	my ($self, $input) = @_;
	my @list = split /\s+/, $input;
	my @out;

	my $sth = $self->{dbh}->prepare("DELETE FROM $self->{table} WHERE word = ?");

	foreach my $entry (@list) {
		my ($w, undef) = _process_word($entry);
		next unless $w;
		$sth->execute($w);
		push @out, $w;
	}

	$self->_sync_if_changed(scalar @out);
	return @out;
}

sub list_regex {
	my ($self, $full) = @_;
	my $sth = $self->{dbh}->prepare("SELECT word FROM $self->{table} ORDER BY word");
	$sth->execute;

	my @out;
	while (my ($word) = $sth->fetchrow_array) {
		if ($full) {
			my ($cleaned, $regex) = _process_word($word);
			push @out, "$cleaned = $regex";
		} else {
			push @out, $word;
		}
	}
	return @out;
}

sub check {
	my ($self, $text) = @_;

	my @relist;
	my %in;
	$self->load_into(\%in, \@relist);

	my $res;
	foreach (@relist) {
		$res .= qq{\\b(?:$_->[1]) |\n};
	}
	$res =~ s/\s*\|\s*$//;
	my $regex = qr/\b($res)/x;

	my $s = uc $text;
	my %uniq;
	my @out = grep { ++$uniq{$_}; $uniq{$_} == 1 ? $_ : () } ($s =~ /($regex)/g);

	dbg("[BadWords_SQL] check '$s' = '" . join(', ', @out) . "'") if isdbg('badword');
	return @out;
}

sub _process_word {
	my ($word) = @_;
	$word = uc $word;
	$word =~ tr/01/OI/;
	my $last = '';
	my @chars;
	for (split //, $word) {
		next if $last eq $_;
		$last = $_;
		push @chars, $_;
	}

	return undef unless @chars;
	my $cleaned = join('', @chars);
	return undef unless $cleaned =~ /^\w+$/;

	my @leet = map { s/O/[O0]/g; s/I/[I1]/g; $_ } @chars;
	my $regex = join '+[\s\W]*', @leet;

	return ($cleaned, $regex);
}

sub load {
	my ($self) = @_;
	my $dbh = $self->{dbh};
	my $table = $self->{table};

	my $file = File::Spec->catfile($main::local_data, 'badword.new');
	return unless -e $file;

	my $sql = ($main::db_backend eq 'mysql')
		? "INSERT IGNORE INTO $table (word) VALUES (?)"
		: "INSERT OR IGNORE INTO $table (word) VALUES (?)";

	my $sth = $dbh->prepare($sql);
	my $count = 0;

	open my $fh, '<', $file or return;
	while (<$fh>) {
		chomp;
		next if /^\s*#/ || !/\S/;
		my ($word, undef) = _process_word($_);
		next unless $word;
		$sth->execute($word);
		$count++;
	}
	close $fh;

	dbg("[BadWords_SQL] $count new badwords added from badword.new");

	#$self->_sync_if_changed($count);
}

sub _sync_if_changed {
	my ($self, $count) = @_;
	return unless $count && $count > 0;
	DXClusterSync::broadcast_load($self->{table});
}

1;
