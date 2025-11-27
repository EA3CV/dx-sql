package DXUser_SQL;

use strict;
use warnings;
use DBI;
use JSON;
use Scalar::Util qw(blessed);
use DXVars;
use DXChannel;
use Encode;
use File::Copy qw(copy move);

#$main::dxdebug = 1;

my $dbh;
my $json = JSON->new->canonical(1);
my $table = 'users';

# Field list
my @FIELDS = qw(
	call sort addr alias annok autoftx bbs bbsaddr believe buddies build clientoutput clientinput connlist
	dxok email ftx group hmsgno homenode isolate K lang lastin lastoper lastping lastseen lat lockout long
	maxconnect name node nopings nothere pagelth passphrase passwd pingint priv prompt qra qth rbnseeme
	registered startt user_interval version wantann wantann_talk wantbeacon wantbeep wantcw wantdx
	wantdxcq wantdxitu wantecho wantemail wantft wantgtk wantlogininfo wantpc16 wantpc9x wantpsk
	wantrbn wantroutepc19 wantrtty wantsendpc16 wanttalk wantusstate wantwcy wantwwv wantwx width xpert
	wantgrid
);

sub init {
	my ($mode) = @_;

	my ($dsn, $user, $pass);

	if ($main::db_backend eq 'sqlite') {
		$dsn  = $main::sqlite_dsn;
		$user = $main::sqlite_dbuser;
		$pass = $main::sqlite_dbpass;

		my ($db_path) = $dsn =~ /dbname=([^;]+)/;
		my $db_missing = !-e $db_path;

		$dbh = DBI->connect($dsn, $user, $pass, {
			RaiseError     => 1,
			AutoCommit     => 1,
			sqlite_unicode => 1,
		}) or die "[DXUser_SQL] SQLite connect error: $DBI::errstr";

		my $needs_init = $db_missing || !_table_exists('users');
		if ($needs_init) {
			print "[DXUser_SQL] Creating SQLite table: $table...\n";
			_create_table_if_needed();
			_import_from_user_json();
		}

	} else {
		my $mysql_db = $main::mysql_db;
		$dsn = "DBI:mysql:host=$main::mysql_host";
		$user = $main::mysql_user;
		$pass = $main::mysql_pass;

		my $dbh_tmp = DBI->connect($dsn, $user, $pass, {
			RaiseError => 1,
			AutoCommit => 1
		}) or die "[DXUser_SQL] MySQL connect error: $DBI::errstr";

		my $db_exists = $dbh_tmp->selectrow_array("SHOW DATABASES LIKE ?", undef, $mysql_db);

		unless ($db_exists) {
			print "[DXUser_SQL] Creating MySQL database $mysql_db...\n";
			$dbh_tmp->do("CREATE DATABASE `$mysql_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
		}

		$dbh_tmp->disconnect;

		$dsn = "DBI:mysql:database=$mysql_db;host=$main::mysql_host";
		$dbh = DBI->connect($dsn, $user, $pass, {
			RaiseError           => 1,
			AutoCommit           => 1,
			mysql_enable_utf8mb4 => 1,
		}) or die "[DXUser_SQL] MySQL connect error: $DBI::errstr";

		my $table_exists = $dbh->selectrow_array("SHOW TABLES LIKE '$table'");
		unless ($table_exists) {
			print "[DXUser_SQL] Creating MySQL $table\n";
			_create_table_if_needed();
			_import_from_user_json();
		}
	}

	return bless {}, __PACKAGE__;
}

sub _create_table_if_needed {
	my $sql;

	if ($main::db_backend eq 'mysql') {
		$sql = qq{
CREATE TABLE IF NOT EXISTS `$table` (
  `call` VARCHAR(16) NOT NULL,
  `sort` CHAR(1) DEFAULT 'U',
  `addr` TEXT DEFAULT NULL,
  `alias` VARCHAR(16) DEFAULT NULL,
  `annok` TINYINT(1) DEFAULT 1,
  `autoftx` TINYINT(1) DEFAULT 0,
  `bbs` VARCHAR(32) DEFAULT NULL,
  `bbsaddr` VARCHAR(32) DEFAULT NULL,
  `believe` LONGTEXT DEFAULT NULL,
  `buddies` LONGTEXT DEFAULT NULL,
  `build` VARCHAR(6) DEFAULT NULL,
  `clientoutput` TEXT DEFAULT NULL,
  `clientinput` TEXT DEFAULT NULL,
  `connlist` LONGTEXT DEFAULT NULL,
  `dxok` TINYINT(1) DEFAULT 1,
  `email` VARCHAR(128) DEFAULT NULL,
  `ftx` TINYINT(1) DEFAULT 0,
  `group` LONGTEXT DEFAULT NULL,
  `hmsgno` INT(11) DEFAULT NULL,
  `homenode` VARCHAR(64) DEFAULT NULL,
  `isolate` TINYINT(1) DEFAULT 0,
  `K` TINYINT(1) DEFAULT 0,
  `lang` VARCHAR(5) DEFAULT 'en',
  `lastin` BIGINT(20) DEFAULT NULL,
  `lastoper` BIGINT(20) DEFAULT NULL,
  `lastping` LONGTEXT DEFAULT NULL,
  `lastseen` BIGINT(20) DEFAULT NULL,
  `lat` VARCHAR(20) DEFAULT NULL,
  `lockout` TINYINT(1) DEFAULT 0,
  `long` VARCHAR(20) DEFAULT NULL,
  `maxconnect` INT(11) DEFAULT NULL,
  `name` VARCHAR(64) DEFAULT NULL,
  `node` VARCHAR(16) DEFAULT NULL,
  `nopings` INT(11) DEFAULT NULL,
  `nothere` TEXT DEFAULT NULL,
  `pagelth` INT(11) DEFAULT NULL,
  `passphrase` VARCHAR(64) DEFAULT NULL,
  `passwd` VARCHAR(32) DEFAULT NULL,
  `pingint` INT(11) DEFAULT NULL,
  `priv` TINYINT(1) DEFAULT 0,
  `prompt` VARCHAR(64) DEFAULT NULL,
  `qra` VARCHAR(8) DEFAULT NULL,
  `qth` VARCHAR(128) DEFAULT NULL,
  `rbnseeme` TINYINT(1) DEFAULT 0,
  `registered` TINYINT(1) DEFAULT 0,
  `startt` BIGINT(20) DEFAULT NULL,
  `user_interval` INT(11) DEFAULT NULL,
  `version` VARCHAR(6) DEFAULT NULL,
  `wantann` TINYINT(1) DEFAULT 1,
  `wantann_talk` TINYINT(1) DEFAULT 1,
  `wantbeacon` TINYINT(1) DEFAULT 0,
  `wantbeep` TINYINT(1) DEFAULT 0,
  `wantcw` TINYINT(1) DEFAULT 0,
  `wantdx` TINYINT(1) DEFAULT 1,
  `wantdxcq` TINYINT(1) DEFAULT 0,
  `wantdxitu` TINYINT(1) DEFAULT 0,
  `wantecho` TINYINT(1) DEFAULT 0,
  `wantemail` TINYINT(1) DEFAULT 1,
  `wantft` TINYINT(1) DEFAULT 0,
  `wantgtk` TINYINT(1) DEFAULT 1,
  `wantlogininfo` TINYINT(1) DEFAULT 0,
  `wantpc16` TINYINT(1) DEFAULT 1,
  `wantpc9x` TINYINT(1) DEFAULT 1,
  `wantpsk` TINYINT(1) DEFAULT 0,
  `wantrbn` TINYINT(1) DEFAULT 0,
  `wantroutepc19` TINYINT(1) DEFAULT 0,
  `wantrtty` TINYINT(1) DEFAULT 0,
  `wantsendpc16` TINYINT(1) DEFAULT 1,
  `wanttalk` TINYINT(1) DEFAULT 1,
  `wantusstate` TINYINT(1) DEFAULT 0,
  `wantwcy` TINYINT(1) DEFAULT 1,
  `wantwwv` TINYINT(1) DEFAULT 1,
  `wantwx` TINYINT(1) DEFAULT 1,
  `wantgrid` TINYINT(1) DEFAULT 0,
  `width` INT(11) DEFAULT NULL,
  `xpert` TINYINT(1) DEFAULT 0,
  PRIMARY KEY (`call`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
		};
	} else {
		# SQLite version
		$sql = qq{
CREATE TABLE IF NOT EXISTS `$table` (
  `call` TEXT PRIMARY KEY,
  `sort` TEXT DEFAULT 'U',
  `addr` TEXT,
  `alias` TEXT,
  `annok` INTEGER DEFAULT 1,
  `autoftx` INTEGER DEFAULT 0,
  `bbs` TEXT,
  `bbsaddr` TEXT,
  `believe` TEXT,
  `buddies` TEXT,
  `build` TEXT,
  `clientoutput` TEXT,
  `clientinput` TEXT,
  `connlist` TEXT,
  `dxok` INTEGER DEFAULT 1,
  `email` TEXT,
  `ftx` INTEGER DEFAULT 0,
  `group` TEXT,
  `hmsgno` INTEGER,
  `homenode` TEXT,
  `isolate` INTEGER DEFAULT 0,
  `K` INTEGER DEFAULT 0,
  `lang` TEXT DEFAULT 'en',
  `lastin` INTEGER,
  `lastoper` INTEGER,
  `lastping` TEXT,
  `lastseen` INTEGER,
  `lat` TEXT,
  `lockout` INTEGER DEFAULT 0,
  `long` TEXT,
  `maxconnect` INTEGER,
  `name` TEXT,
  `node` TEXT,
  `nopings` INTEGER,
  `nothere` TEXT,
  `pagelth` INTEGER,
  `passphrase` TEXT,
  `passwd` TEXT,
  `pingint` INTEGER,
  `priv` INTEGER DEFAULT 0,
  `prompt` TEXT,
  `qra` TEXT,
  `qth` TEXT,
  `rbnseeme` INTEGER DEFAULT 0,
  `registered` INTEGER DEFAULT 0,
  `startt` INTEGER,
  `user_interval` INTEGER,
  `version` TEXT,
  `wantann` INTEGER DEFAULT 1,
  `wantann_talk` INTEGER DEFAULT 1,
  `wantbeacon` INTEGER DEFAULT 0,
  `wantbeep` INTEGER DEFAULT 0,
  `wantcw` INTEGER DEFAULT 0,
  `wantdx` INTEGER DEFAULT 1,
  `wantdxcq` INTEGER DEFAULT 0,
  `wantdxitu` INTEGER DEFAULT 0,
  `wantecho` INTEGER DEFAULT 0,
  `wantemail` INTEGER DEFAULT 1,
  `wantft` INTEGER DEFAULT 0,
  `wantgtk` INTEGER DEFAULT 1,
  `wantlogininfo` INTEGER DEFAULT 0,
  `wantpc16` INTEGER DEFAULT 1,
  `wantpc9x` INTEGER DEFAULT 1,
  `wantpsk` INTEGER DEFAULT 0,
  `wantrbn` INTEGER DEFAULT 0,
  `wantroutepc19` INTEGER DEFAULT 0,
  `wantrtty` INTEGER DEFAULT 0,
  `wantsendpc16` INTEGER DEFAULT 1,
  `wanttalk` INTEGER DEFAULT 1,
  `wantusstate` INTEGER DEFAULT 0,
  `wantwcy` INTEGER DEFAULT 1,
  `wantwwv` INTEGER DEFAULT 1,
  `wantwx` INTEGER DEFAULT 1,
  `wantgrid` INTEGER DEFAULT 0,
  `width` INTEGER,
  `xpert` INTEGER DEFAULT 0
);
		};
	}

	$dbh->do($sql);
}

sub get {
	my ($call) = @_;
	$call = uc $call;
	my $sql = "SELECT * FROM `$table` WHERE `call` = ?";
	my $sth = $dbh->prepare($sql);
	$sth->execute($call);
	my $row = $sth->fetchrow_hashref;
	return undef unless $row;

	my %obj = %$row;

	# Lista explícita de campos que SÍ son JSON
	my %json_fields = map { $_ => 1 } qw(
		believe
		buddies
		connlist
		email
		group
	);

	foreach my $key (keys %obj) {
		next unless defined $obj{$key};

		if ($json_fields{$key}) {
			my $val = $obj{$key};
			next if $val eq '' or $val eq 'null';  # evitar decode vacío
			eval {
				$obj{$key} = $json->decode($val);
			};
			if ($@) {
				warn "[DXUser_SQL] JSON decode failed for $key on $call: $@\n";
				$obj{$key} = [];
			}
		} else {
			$obj{$key} = Encode::decode('utf8', $obj{$key})
			  unless Encode::is_utf8($obj{$key});
		}
	}

	my %defaults = %{ __PACKAGE__->alloc($call) };
	foreach my $k (keys %defaults) {
		$obj{$k} = $defaults{$k} unless exists $obj{$k};
	}

	return bless \%obj, 'DXUser';
}

sub alloc {
	my ($class, $call) = @_;
	my $self = {
		call           => uc $call,
		sort           => 'U',
		group          => ['local'],
		registered     => 0,
		priv           => 0,
		lockout        => 0,
		isolate        => 0,
		lang           => 'en',
		K              => 0,
		annok          => 1,
		dxok           => 1,
		rbnseeme       => 0,
		wantann        => 1,
		wantann_talk   => 1,
		wantbeacon     => 0,
		wantbeep       => 0,
		wantcw         => 0,
		wantdx         => 1,
		wantdxcq       => 0,
		wantdxitu      => 0,
		wantecho       => 0,
		wantemail      => 1,
		wantft         => 0,
		wantgrid       => 0,
		wantgtk        => 1,
		wantlogininfo  => 0,
		wantpc16       => 1,
		wantpc9x       => 1,
		wantpsk        => 0,
		wantrbn        => 0,
		wantrtty       => 0,
		wantsendpc16   => 1,
		wanttalk       => 1,
		wantusstate    => 0,
		wantwcy        => 1,
		wantwwv        => 1,
		wantwx         => 1,
	};
	return bless $self, 'DXUser';
}

sub put {
	my ($self) = @_;
	my $call = uc $self->{call};
	return unless $call;

	$self->{lastseen} = $main::systime unless $self->{lastseen};

	my %json_fields = map { $_ => 1 } qw(
		believe
		buddies
		connlist
		email
		group
	);

	if ($main::bulk_import) {
		# Optimización para inserción rápida (sin comprobaciones)
		my @columns = @FIELDS;
		my @values;

		foreach my $col (@columns) {
			my $val = $self->{$col};
			if ($json_fields{$col}) {
				push @values, defined $val ? $json->encode($val) : undef;
			} else {
				if (defined $val && !Encode::is_utf8($val)) {
					$val = Encode::decode('utf8', $val);
				}
				push @values, $val;
			}
		}

		my $sql;
		if ($main::db_backend eq 'mysql') {
			$sql = "INSERT INTO `$table` (" . join(",", map { "`$_`" } @columns) .
				   ") VALUES (" . join(",", ("?") x @columns) . ")" .
				   " ON DUPLICATE KEY UPDATE " .
				   join(", ", map { "`$_`=VALUES(`$_`)" } @columns);
		} else {
			# SQLite: REPLACE = DELETE + INSERT
			$sql = "REPLACE INTO `$table` (" . join(",", map { "`$_`" } @columns) .
				   ") VALUES (" . join(",", ("?") x @columns) . ")";
		}

		my $sth = $dbh->prepare($sql);
		$sth->execute(@values);

		print "[DXUser_SQL] Imported/Updated $call\n" if $main::dxdebug;
		return 1;
	}

	# Modo normal: solo actualiza si hay cambios
	my $sth = $dbh->prepare("SELECT * FROM `$table` WHERE `call` = ?");
	$sth->execute($call);
	my $current = $sth->fetchrow_hashref;

	unless ($current) {
		# No existe: insertar normalmente
		my @columns = @FIELDS;
		my @values;

		foreach my $col (@columns) {
			my $val = $self->{$col};
			if ($json_fields{$col}) {
				push @values, defined $val ? $json->encode($val) : undef;
			} else {
				if (defined $val && !Encode::is_utf8($val)) {
					$val = Encode::decode('utf8', $val);
				}
				push @values, $val;
			}
		}

		my $sql = "INSERT INTO `$table` (" . join(",", map { "`$_`" } @columns) .
				  ") VALUES (" . join(",", ("?") x @columns) . ")";
		my $sth2 = $dbh->prepare($sql);
		$sth2->execute(@values);

		print "[DXUser_SQL] Inserted $call\n" if $main::dxdebug;
		return 1;
	}

	# Existe: comparar campos y actualizar solo si cambian
	my %changes;
	foreach my $f (@FIELDS) {
		my $new_val = $self->{$f};
		my $old_val = $current->{$f};

		if ($json_fields{$f}) {
			$new_val = $json->encode($new_val || {});
			$old_val = $old_val || '';
		} else {
			$new_val = '' unless defined $new_val;
			$old_val = '' unless defined $old_val;
		}

		next if $new_val eq $old_val;
		$changes{$f} = $self->{$f};
	}

	return 1 unless %changes;

	my @columns = keys %changes;
	my @values;

	foreach my $col (@columns) {
		my $val = $changes{$col};
		if ($json_fields{$col}) {
			push @values, defined $val ? $json->encode($val) : undef;
		} else {
			if (defined $val && !Encode::is_utf8($val)) {
				$val = Encode::decode('utf8', $val);
			}
			push @values, $val;
		}
	}

	my $set_clause = join(", ", map { "`$_` = ?" } @columns);
	my $sql = "UPDATE `$table` SET $set_clause WHERE `call` = ?";
	push @values, $call;

	my $sth2 = $dbh->prepare($sql);
	$sth2->execute(@values);

	print "[DXUser_SQL] Updated $call: " . join(", ", @columns) . "\n" if $main::dxdebug;
	return 1;
}

sub new {
	my ($class, $call) = @_;
	my $self = $class->alloc($call);
	$self->put;
	return $self;
}

sub del {
	my ($self) = @_;
	my $call = uc $self->{call};
	my $sql = "DELETE FROM `$table` WHERE `call` = ?";
	my $sth = $dbh->prepare($sql);
	$sth->execute($call);
	return 1;
}

sub close {
	my ($self, $startt, $ip) = @_;
	$self->{lastin} = $main::systime;
	my $ref = [ $startt || $self->{startt}, $main::systime ];
	push @$ref, $ip if $ip;
	push @{$self->{connlist}}, $ref;
	shift @{$self->{connlist}} if @{$self->{connlist}} > $DXUser::maxconnlist;
	$self->put;
}

sub get_all_calls {
	my $sth = $dbh->prepare("SELECT `call` FROM `$table`");
	$sth->execute();
	my @calls;
	while (my ($call) = $sth->fetchrow_array) {
		push @calls, $call;
	}
	return @calls;
}

sub sync {
	my ($self) = @_;
	return put($self) if $self && ref($self) eq 'DXUser';
	return 1;
}

sub export {
	my $name = 'user_json';
	my $fn = $name =~ m{/} ? $name : "$main::local_data/$name";

	require IO::File;
	require Time::HiRes;
	require File::Copy;

	print "[DXUser_SQL] Exporting users to $fn...\n";

	copy($fn, "$fn.bak") if -e $fn;

	my $ta = [Time::HiRes::gettimeofday];
	my $count = 0;

	my $fh = IO::File->new(">$fn") or return "Cannot open $fn ($!)";
	binmode $fh, ":utf8";

	use DXUser ();
	print $fh DXUser::export_preamble() if defined &DXUser::export_preamble;

	foreach my $call (get_all_calls()) {
		my $user = get($call);
		next unless $user;

		my %filtered;
		foreach my $field ($user->fields) {
			next unless exists $user->{$field};

			my $val = $user->{$field};

			next if !defined $val;
			next if (!ref($val) && $val eq '');
			next if (ref($val) eq 'ARRAY' && !@$val);
			next if (ref($val) eq 'HASH'  && !%$val);

			$filtered{$field} = $val;
		}

		my $json_str = eval {
			'{' .
			join(',', map {
				my $k = $_;
				my $v = $filtered{$k};
				my $jval = $json->encode($v);
				$json->encode($k) . ':' . $jval;
			} sort keys %filtered)
			. '}';
		};
		if ($@) {
			warn "[DXUser_SQL] JSON encode error for $call: $@";
			next;
		}

		print $fh "$call\t$json_str\n";
		++$count;
	}

	$fh->close;

	my $diff = Time::HiRes::tv_interval($ta);
	my $s = "Exported $count users to $fn in ${diff}s\n";
	print "[DXUser_SQL] $s";
	return $s;
}

sub _table_exists {
	my ($t) = @_;
	if ($main::db_backend eq 'sqlite') {
		my $sth = $dbh->prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?");
		$sth->execute($t);
		my ($exists) = $sth->fetchrow_array;
		return defined $exists;
	} else {
		my $sth = $dbh->prepare("SHOW TABLES LIKE ?");
		$sth->execute($t);
		my ($exists) = $sth->fetchrow_array;
		return defined $exists;
	}
}

sub _import_from_user_json {
	print "[DXUser_SQL] Importing users from user_json...\n";

	my $file = "$main::root/local_data/user_json";
	return unless -e $file;

	open my $fh, '<:encoding(UTF-8)', $file or do {
		warn "[DXUser_SQL] Cannot open $file: $!";
		return;
	};

	# Iniciar transacción si es posible
	$dbh->begin_work;

	local $main::bulk_import = 1;

	my %max_lengths = (
		call         => 16,
		sort         => 1,
		alias        => 16,
		bbs          => 32,
		bbsaddr      => 32,
		build        => 6,
		clientoutput => undef,
		clientinput  => undef,
		email        => 128,
		homenode     => 64,
		lang         => 5,
		lat          => 20,
		long         => 20,
		name         => 64,
		node         => 16,
		passphrase   => 64,
		passwd       => 32,
		prompt       => 64,
		qra          => 8,
		qth          => 128,
		version      => 6,
	);

	my $count = 0;
	while (my $line = <$fh>) {
		chomp $line;
		next unless $line =~ /^\s*([^\t]+)\t(.+)$/;
		my ($call, $json_str) = ($1, $2);

		my $data = eval { $json->decode($json_str) };
		next unless $data && ref $data eq 'HASH';

		# Completar con valores por defecto
		my %defaults = %{ DXUser_SQL->alloc($call) };
		foreach my $k (keys %defaults) {
			$data->{$k} = $defaults{$k} unless exists $data->{$k};
		}

		# Recortar campos que superen la longitud máxima
		foreach my $k (keys %max_lengths) {
			next unless exists $data->{$k};
			my $max = $max_lengths{$k};
			next unless defined $max;
			if (defined $data->{$k} && length($data->{$k}) > $max) {
				$data->{$k} = substr($data->{$k}, 0, $max);
			}
		}

		my $user = bless $data, 'DXUser';
		DXUser_SQL::put($user);
		$count++;
	}

	$dbh->commit;
	close $fh;

	print "[DXUser_SQL] Imported $count users from user_json\n";
}

sub recover {
	return;
}

sub fields {
	my ($self) = @_;
	return @FIELDS;
}

1;
