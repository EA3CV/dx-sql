#
# unset list of bad dx callsigns
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
#
my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->remotecmd;
# are we permitted?
return (1, $self->msg('e5')) if $self->priv < 6;

my @words = split /\s+/, uc $line;
my @out;
my $count = 0;
foreach my $w (@words) {
	my @in;
	
	unless (@in = BadWords::check($w)) {
		push @out, "BadWord $w not defined, ignored";
	} else {
		@in = BadWords::del_regex($w);
		push @out, "BadWord $w removed";
		$count++;
	}
}
if ($count) {
	BadWords::generate_regex();
	BadWords::put();
}
return (1, @out);

