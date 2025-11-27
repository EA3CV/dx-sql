#
# Search for bad words in strings
#
# Copyright (c) 2000 Dirk Koopman
#

package BadWords;

use strict;
use warnings;

use DXUtil;
use DXVars;
use DXDebug;
use IO::File;

our $regex;       # global regex generated
our @relist;      # list of [word, regex]
my  %in;          # hash of words viewed

my $self = {};    # instance
$self->{_db} = undef;

# Main interface

sub load {
	%in = ();
	@relist = ();
	$regex = '';

	if ($main::db_backend && $main::db_backend ne 'file') {
		require BadWords_SQL;
		$self->{_db} = BadWords_SQL->new();
		$self->{_db}->load();  # <-- aquí se carga solo lo nuevo desde badword.new
		$self->{_db}->load_into(\%in, \@relist);  # luego genera los datos en memoria
		generate_regex();
		dbg("BadWords: Loaded from SQL backend: $main::db_backend");
		return;
	}

	$self->{_db} = undef;

	my @inw;
	my @out;
	my $wasold;

	my $newfn = localdata("badword.new");
	filecopy("$main::data/badword.new.issue", $newfn) unless -e $newfn;
	if (-e $newfn) {
		dbg("BadWords: Found new style badword.new file");
		my $fh = IO::File->new($newfn);
		if ($fh) {
			while (<$fh>) {
				chomp;
				next if /^\s*\#/;
				add_regex(uc $_);
			}
			$fh->close;
			@relist = sort {$a->[0] cmp $b->[0]} @relist;
			dbg("BadWords: " . scalar @relist . " new style badwords read");
		} else {
			my $l = "BadWords: can't open $newfn $!";
			dbg($l);
			push @out, $l;
			return @out;
		}
	} else {
		my $bwfn = localdata("badword");
		filecopy("$main::data/badword.issue", $bwfn) unless -e $bwfn;

		dbg("BadWords: Using old style badword file");
		my $fh = IO::File->new($bwfn);
		if ($fh) {
			my $line = 0;
			while (<$fh>) {
				chomp;
				++$line;
				next if /^\s*\#/;
				unless (/\w+\s+=>\s+\d+,/) {
					dbg("BadWords: syntax error in $bwfn:$line '$_'");
					next;
				}
				my @line = split /\s+/, uc $_;
				shift @line unless $line[0];
				push @inw, $line[0];
			}
			$fh->close;
		} else {
			my $l = "BadWords: can't open $bwfn $!";
			dbg($l);
			push @out, $l;
			return @out;
		}

		my $regexfn = localdata("badw_regex");
		filecopy("$main::data/badw_regex.gb.issue", $regexfn) unless -e $regexfn;
		dbg("BadWords: Using old style badw_regex file");
		$fh = IO::File->new($regexfn);
		if ($fh) {
			while (<$fh>) {
				chomp;
				next if /^\s*\#/ || /^\s*$/;
				push @inw, split /\s+/, uc $_;
			}
			$fh->close;
		} else {
			my $l = "BadWords: can't open $regexfn $!";
			dbg($l);
			push @out, $l;
			return @out;
		}

		++$wasold;
	}

	@inw = sort @inw;
	for (@inw) {
		add_regex($_);
	}

	generate_regex();
	put() if $wasold;

	return @out;
}

sub put {
	return $self->{_db}->put() if $self->{_db};

	my @out;
	my $newfn = localdata("badword.new");
	my $fh = IO::File->new(">$newfn");
	if ($fh) {
		dbg("BadWords: Put new badword.new file");
		@relist = sort {$a->[0] cmp $b->[0]} @relist;
		for (@relist) {
			print $fh "$_->[0]\n";
		}
		$fh->close;
	} else {
		my $l = "BadWords: can't open $newfn $!";
		dbg($l);
		push @out, $l;
		return @out;
	}
}

sub add_regex {
	return $self->{_db}->add_regex(@_) if $self->{_db};

	my @list = split /\s+/, shift;
	my @out;

	for (@list) {
		my $w = uc $_;
		$w = _cleanword($w);
		next unless $w && $w =~ /^\w+$/;
		next if $in{$w};
		next if _slowcheck($w);

		my @l = map { s/O/[O0]/g; s/I/[I1]/g; $_ } split //, $w;
		my $e = join '+[\s\W]*', @l;
		my $q = $e;
		push @relist, [$w, $q];
		$in{$w} = $q;
		dbg("$w = $q") if isdbg('badword');
		push @out, $w;
	}
	return @out;
}

sub del_regex {
	return $self->{_db}->del_regex(@_) if $self->{_db};

	my @list = split /\s+/, shift;
	my @out;

	for (@list) {
		my $w = uc $_;
		$w = _cleanword($w);
		next unless $in{$w};
		delete $in{$w};
		@relist = grep { $_->[0] ne $w } @relist;
		push @out, $w;
	}
	return @out;
}

sub list_regex {
	return $self->{_db}->list_regex(@_) if $self->{_db};

	my $full = shift;
	return map { $full ? "$_->[0] = $_->[1]" : $_->[0] } @relist;
}

sub check {
	return $self->{_db}->check(@_) if $self->{_db};

	my $s = uc shift;
	my @out;
	if ($regex) {
		my %uniq;
		@out = grep { ++$uniq{$_}; $uniq{$_} == 1 ? $_ : undef } ($s =~ /($regex)/g);
		dbg("BadWords: Check '$s' = '" . join(', ', @out) . "'") if isdbg('badword');
		return @out;
	}
	return _slowcheck($s) if @relist;
	return;
}

# Auxiliary functions

sub generate_regex {
	my $res = '';
	@relist = sort { $a->[0] cmp $b->[0] } @relist;

	for (@relist) {
		$res .= qq{\\b(?:$_->[1]) |\n};
	}

	if ($res ne '') {
		$res =~ s/\s*\|\s*$//;
		$regex = qr/\b($res)/x;
	} else {
		$regex = undef;
	}
}

sub _cleanword {
	my $w = uc shift;
	$w =~ tr/01/OI/;
	my $last = '';
	my @w;
	for (split //, $w) {
		next if $last eq $_;
		$last = $_;
		push @w, $_;
	}
	return @w ? join('', @w) : '';
}

sub _slowcheck {
	my $w = shift;
	my @out;
	for (@relist) {
		push @out, $w =~ /\b($_->[1])/;
	}
	return @out;
}

1;
