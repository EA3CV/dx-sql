package Filter_SQL;

use strict;
use warnings;
use DBI;
use DXVars;
use DXJSON;
use DXDebug;
use DXUtil qw(readfilestr);
use File::Find;

my $json = DXJSON->new->indent(1);
my $table = 'filters';

sub new {
	my ($class, $sort, $call, $flag) = @_;
	$flag = $flag ? "in_" : "";
	my $self = {
		sort    => $sort,
		name    => "$flag$call.pl",
		filters => {},
	};
	bless $self, $class;

	$self->_load_from_db();
	return $self;
}

sub _get_dbh {
	my $dsn  = $main::db_backend eq 'sqlite' ? $main::sqlite_dsn : "dbi:mysql:database=$main::mysql_db;host=$main::mysql_host";
	my $user = $main::db_backend eq 'sqlite' ? $main::sqlite_dbuser : $main::mysql_user;
	my $pass = $main::db_backend eq 'sqlite' ? $main::sqlite_dbpass : $main::mysql_pass;
	return DBI->connect($dsn, $user, $pass, {
		RaiseError => 1,
		PrintError => 0,
		AutoCommit => 1,
		mysql_enable_utf8mb4 => 1,
		sqlite_unicode       => 1,
	});
}

sub ensure_table_exists {
	my $dbh = _get_dbh();
	return unless $dbh;

	my $driver = $dbh->{Driver}->{Name};
	my $sql;

	if ($driver eq 'mysql') {
		$sql = qq{
			CREATE TABLE IF NOT EXISTS $table (
				id INT AUTO_INCREMENT PRIMARY KEY,
				list_name VARCHAR(255) NOT NULL,
				sort VARCHAR(64) NOT NULL,
				filter_key VARCHAR(64) NOT NULL,
				rule_type VARCHAR(16) NOT NULL,
				user_expr TEXT,
				asc_expr TEXT,
				created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
			) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
		};
	}
	elsif ($driver eq 'SQLite') {
		$sql = qq{
			CREATE TABLE IF NOT EXISTS $table (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				list_name TEXT NOT NULL,
				sort TEXT NOT NULL,
				filter_key TEXT NOT NULL,
				rule_type TEXT NOT NULL,
				user_expr TEXT,
				asc_expr TEXT,
				created_at TEXT DEFAULT CURRENT_TIMESTAMP
			);
		};
	} else {
		die "[Filter_SQL] Unsupported DB driver: $driver";
	}

	my $exists = 0;
	{
		local $dbh->{RaiseError} = 0;
		local $dbh->{PrintError} = 0;
		my $sth = $dbh->prepare("SELECT 1 FROM $table LIMIT 1");
		$exists = 1 if $sth && $sth->execute;
	}

	unless ($exists) {
		dbg("[Filter_SQL] Table '$table' not found, creating and importing from files...");
		$dbh->do($sql);
		_migrate_from_files($dbh);
	}

	$dbh->disconnect;
}

sub _migrate_from_files {
	my ($dbh) = @_;
	my $base_dir = "$main::root/filter";

	find(sub {
		return unless -f $_ && $_ =~ /\.pl$/;
		my $file = $File::Find::name;
		my ($sort) = $File::Find::dir =~ m{/filter/([^/]+)};
		my $content = readfilestr($file);
		unless ($content && $content =~ /^\s*[\[{]/) {
			dbg("[Filter_SQL] Skipping invalid or empty file: $file");
			return;
		}

		my $data = eval { $json->decode($content) };
		if ($@ || ref $data ne 'HASH') {
			dbg("[Filter_SQL] JSON decode error in $file: $@");
			return;
		}

		(my $list_name = $data->{name}) =~ s/\.pl$//;

		foreach my $key (grep /^filter/, keys %$data) {
			for my $type (qw(reject accept)) {
				next unless exists $data->{$key}{$type};
				my $u = $data->{$key}{$type}{user};
				my $a = $data->{$key}{$type}{asc};
				next unless defined $u && defined $a;
				my $ins = $dbh->prepare("INSERT INTO $table (list_name, sort, filter_key, rule_type, user_expr, asc_expr) VALUES (?, ?, ?, ?, ?, ?)");
				$ins->execute($list_name, $sort, $key, $type, $u, $a);
			}
		}
	}, $base_dir);
}

sub _load_from_db {
	my $self = shift;
	my $dbh = _get_dbh();
	return unless $dbh;

	(my $list_name = $self->{name}) =~ s/\.pl$//;

	my $sth = $dbh->prepare("SELECT filter_key, rule_type, user_expr, asc_expr FROM $table WHERE list_name = ? AND sort = ?");
	$sth->execute($list_name, $self->{sort});
	while (my ($key, $rtype, $user, $asc) = $sth->fetchrow_array) {
		$self->{filters}{$key}{$rtype} = {
			user => $user,
			asc  => $asc,
			code => undef,
		};
	}
	$dbh->disconnect;
}

sub getfilkeys {
	my $self = shift;
	return grep { /^filter/ } keys %{ $self->{filters} };
}

sub getfilters {
	my $self = shift;
	return values %{ $self->{filters} };
}

sub compile {
	my ($self, $key, $rtype) = @_;
	my $rule = $self->{filters}{$key}{$rtype};
	return unless $rule && $rule->{asc};
	my $s = $rule->{asc};
	$s =~ s/\$r/\$_[0]/g;
	$rule->{code} = eval "sub { $s }";
	dbg("[Filter_SQL] Error compiling $key $rtype: $@") if $@;
	return $@;
}

sub write {
	my $self = shift;
	my $dbh = _get_dbh();
	return "[Filter_SQL] Error no DBH" unless $dbh;

	(my $list_name = $self->{name}) =~ s/\.pl$//;

	my $sth_del = $dbh->prepare("DELETE FROM $table WHERE list_name = ? AND sort = ?");
	$sth_del->execute($list_name, $self->{sort});

	my $sth_ins = $dbh->prepare("INSERT INTO $table (list_name, sort, filter_key, rule_type, user_expr, asc_expr) VALUES (?, ?, ?, ?, ?, ?)");
	for my $key ($self->getfilkeys) {
		for my $rtype (qw(reject accept)) {
			next unless $self->{filters}{$key}{$rtype};
			my $rule = $self->{filters}{$key}{$rtype};
			$sth_ins->execute($list_name, $self->{sort}, $key, $rtype, $rule->{user}, $rule->{asc});
		}
	}
	$dbh->disconnect;
}

sub delete {
	my ($sort, $call, $flag, $fno, $dxchan) = @_;
	my $flag_prefix = $flag ? 'in_' : '';
	my $name = "$flag_prefix$call";
	$name =~ s/\.pl$//;

	my $dbh = _get_dbh();
	return unless $dbh;

	if ($fno eq 'all') {
		my $sth = $dbh->prepare("DELETE FROM $table WHERE list_name = ? AND sort = ?");
		$sth->execute($name, $sort);
	} else {
		my $sth = $dbh->prepare("DELETE FROM $table WHERE list_name = ? AND sort = ? AND filter_key = ?");
		$sth->execute($name, $sort, "filter$fno");
	}
	$dbh->disconnect;
}

sub it {
	my ($self, @args) = @_;
	my $r = 1;
	my $hops = $self->{hops};

	foreach my $key (sort $self->getfilkeys) {
		my $filter = $self->{filters}{$key};
		for my $rtype (qw(reject accept)) {
			next unless $filter->{$rtype} && $filter->{$rtype}{code};
			if ($rtype eq 'reject' && $filter->{$rtype}{code}->(\@args)) {
				return (0, $hops);
			} elsif ($rtype eq 'accept' && !$filter->{$rtype}{code}->(\@args)) {
				return (0, $hops);
			}
		}
	}
	return (1, $hops);
}

sub print {
	my $self = shift;
	my @out;

	my @keys = $self->getfilkeys;
	return @out unless @keys;

	(my $basename = $self->{name}) =~ s/\.pl$//;
	push @out, join(' ', $basename, ':', $self->{sort});

	for my $key (sort @keys) {
		my $f = $self->{filters}{$key};
		push @out, " $key reject $f->{reject}{user}" if $f->{reject};
		push @out, " $key accept $f->{accept}{user}" if $f->{accept};
	}
	return @out;
}

sub install {
	my ($self, $force, $dxchan) = @_;

	my $filepath = "$main::root/filter/$self->{sort}/$self->{name}";
	if (-e $filepath) {
		unlink $filepath;
		dbg("[Filter_SQL] Removed legacy file: $filepath") if $force;
	}

	$self->write;
}

1;
