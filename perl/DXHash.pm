#
# a class for setting 'bad' (or good) things
#
# This is really a general purpose list handling
# thingy for determining good or bad objects like
# callsigns. It is for storing things "For Ever".
#
# Things entered into the list are always upper
# cased.
#
# The files that are created live in /spider/local_data (was data)
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#

package DXHash;

use strict;
use warnings;
use DXVars;
use DXUtil;
use DXDebug;

sub new {
	my ($pkg, $name) = @_;

	die "DXHash->new: missing list name" unless defined $name;

	if ($main::db_backend && ($main::db_backend eq 'mysql' || $main::db_backend eq 'sqlite')) {
		require DXHash_SQL;
		return bless { name => $name, _db => DXHash_SQL->new($name) }, $pkg;
	}

	localdata_mv($name);
	my $s = readfilestr($main::local_data, $name);
	my $self;

	if ($s) {
		eval { $self = eval $s };
		if ($@) {
			dbg("error reading $name in DXHash: $@");
			$self = undef;  # Puedes forzar die si prefieres no continuar: die ...
		}
	}

	$self ||= { name => $name };
	return bless $self, $pkg;
}

sub put   { my $s = shift; return $s->{_db}->put(@_)    if $s->{_db}; _put($s, @_);   }
sub add   { my $s = shift; return $s->{_db}->add(@_)    if $s->{_db}; _add($s, @_);   }
sub del   { my $s = shift; return $s->{_db}->del(@_)    if $s->{_db}; _del($s, @_);   }
sub in    { my $s = shift; return $s->{_db}->in(@_)     if $s->{_db}; _in($s, @_);    }
sub set   { my $s = shift; return $s->{_db}->set(@_)    if $s->{_db}; _set($s, @_);   }
sub unset { my $s = shift; return $s->{_db}->unset(@_)  if $s->{_db}; _unset($s, @_); }
sub show  { my $s = shift; return $s->{_db}->show(@_)   if $s->{_db}; _show($s, @_);  }

sub _put {
	my $self = shift;
	writefilestr($main::local_data, $self->{name}, undef, $self);
}

sub _add {
	my $self = shift;
	my $n = uc shift;
	my $t = shift || $main::systime;
	$self->{$n} = $t;

	my $nn = $n;
	$nn =~ s|(?:-\d+)?(?:/\w)?$||;
	$self->{$nn} = $t unless exists $self->{$nn} || $n eq $nn;
}

sub _del {
	my $self = shift;
	my $n = uc shift;
	my $exact = shift;
	delete $self->{$n};
	return if $exact;

	my $nn = $n;
	$nn =~ s|(?:-\d+)?(?:/\w)?$||;
	delete $self->{"$nn-$_"} for 0..99;
}

sub _in {
	my $self = shift;
	my $n = uc shift;
	my $exact = shift;

	return 1 if exists $self->{$n};
	return 0 if $exact;

	$n =~ s/-\d+$//;
	return exists $self->{$n};
}

sub _set {
	my ($self, $priv, $noline, $dxchan, $line) = @_;
	return (1, $dxchan->msg('e5')) unless $dxchan->priv >= $priv;
	my @f = split /\s+/, $line;
	return (1, $noline) unless @f;

	my @out;
	foreach my $f (@f) {
		if (_in($self, $f, 1)) {
			push @out, $dxchan->msg('hasha', uc $f, $self->{name});
		} else {
			_add($self, $f, $main::systime);
			push @out, $dxchan->msg('hashb', uc $f, $self->{name});
		}
	}
	_put($self);
	return (1, @out);
}

sub _unset {
	my ($self, $priv, $noline, $dxchan, $line) = @_;
	return (1, $dxchan->msg('e5')) unless $dxchan->priv >= $priv;
	my @f = split /\s+/, $line;
	return (1, $noline) unless @f;

	my @out;
	foreach my $f (@f) {
		if (_in($self, $f, 1)) {
			_del($self, $f, 1);
			push @out, $dxchan->msg('hashc', uc $f, $self->{name});
		} else {
			push @out, $dxchan->msg('hashd', uc $f, $self->{name});
		}
	}
	_put($self);
	return (1, @out);
}

sub _show {
	my ($self, $priv, $dxchan) = @_;
	return (1, $dxchan->msg('e5')) unless $dxchan->priv >= $priv;

	my @out;
	foreach my $k (sort grep { $_ ne 'name' } keys %$self) {
		push @out, $dxchan->msg('hashe', $k, cldatetime($self->{$k}));
	}
	return (1, @out);
}

sub reload {
	my ($self) = @_;

	if ($self->{_db}) {
		return $self->{_db}->reload();  # delega en DXHash_SQL
	}

	# backend tipo file: recarga el hash desde el disco
	localdata_mv($self->{name});
	my $s = readfilestr($main::local_data, $self->{name});
	if ($s) {
		my $newdata;
		eval { $newdata = eval $s };
		if ($@) {
			dbg("DXHash: error reloading $self->{name}: $@");
			return 0;
		}

		# Actualizamos las claves (sin perder la referencia del objeto original)
		foreach my $k (keys %$self) {
			delete $self->{$k} unless $k eq '_db';
		}
		@$self{keys %$newdata} = values %$newdata;
		return 1;
	}

	return 0;
}

1;
