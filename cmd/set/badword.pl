#
# set list of bad dx callsigns
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
	
	if (@in = BadWords::check($w)) {
		push @out, "BadWord $w already matched by '$in[0]', ignored";
	} else {
		@in = BadWords::add_regex($w);
		push @out, "BadWord $w added as '$in[0]'";
		$count++;
	}
}
if ($count) {
	BadWords::generate_regex();
	BadWords::put();
}
return (1, @out);
		
