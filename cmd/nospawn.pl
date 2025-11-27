#!/usr/bin/perl
#
# pretend that you are another user, useful for reseting
# those silly things that people insist on getting wrong
# like set/homenode et al
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
my ($self, $line) = @_;

my $mycall = $self->call;


if ($self->priv < 2) {
	Log('DXCommand', "$mycall is trying to nospawn $line locally");
	return (1, $self->msg('e5'));
}
if ($self->remotecmd || $self->inscript) {
	Log('DXCommand', "$mycall is trying to nospawn remotely");
	return (1, $self->msg('e5'));
}

Log('DXCommand', "nospawn '$line' by $mycall");
++$self->{_nospawn};
my @out = $self->run_cmd($line);
$self->{_nospawn} = 0 if exists $self->{_nospawn} && --$self->{_nospawn} <= 0;

return (1, @out);
