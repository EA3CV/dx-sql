#
# show your buddies 
#
# Copyright (c) 2006 - Dirk Koopman G1TLH
#
#
#

my ($self) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 1;

my @out;
my @l;

my $u = DXUser::get($self->{call});
return (1, "User not found") unless $u;

my $buddies = $u->buddies;
$buddies = [] unless ref($buddies) eq 'ARRAY';

foreach my $call (@$buddies) {
	if (@l >= 5) {
		push @out, sprintf "%-12s %-12s %-12s %-12s %-12s", @l;
		@l = ();
	}
	push @l, $call;
}

if (@l) {
	push @l, "" while @l < 5;
	push @out, sprintf "%-12s %-12s %-12s %-12s %-12s", @l;
}

push @out, "Total buddies: " . scalar(@$buddies);
return (1, @out);
