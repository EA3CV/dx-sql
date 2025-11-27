#
# show list of bad dx callsigns
#
# Copyright (c) 2023 - Dirk Koopman G1TLH
#
#
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->remotecmd;
# are we permitted?
return (1, $self->msg('e5')) if $self->priv < 6;

my @out;
my @l;
my $count = 0;
my @words = BadWords::check($line);
my $cand;
my $w;

push @out, "Words: " . join ',', @words; 

if ($line =~ /^\s*full/i || @words) {
	foreach $w (BadWords::list_regex(1)) {
		++$count;
		if ($line =~ /^\s*full/) {
			push @out, $w; 
		} elsif (@words) {
		    ($cand) = split /\s+/, $w;
			#push @out, "cand: $cand"; 
			push @out, $w if grep {$cand eq $_} @words; 
		}
	}
}
else {
	foreach my $w (BadWords::list_regex()) {
		++$count;
		if (@l >= 5) {
			push @out, sprintf "%-12s %-12s %-12s %-12s %-12s", @l;
			@l = ();
		}
		push @l, $w;
	}
	push @l, "" while @l < 5;
	push @out, sprintf "%-12s %-12s %-12s %-12s %-12s", @l;
}

push @out, "$count BadWords";
	
return (1, @out);

