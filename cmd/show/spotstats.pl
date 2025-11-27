# show the current received spot stats including
#   pc11s
#   pc61s
#   percentage of pc11s in the total no of (unique) pc11+pc61 spots
#   no of pc11s promoted to pc61 by stored ip address
#   no of pc11s promoted to pc61 because a pc61 with the same data came in just after the pc11
#   no of pc11 promoted to pc61 by any means
#   percentage of pc11 promoted to pc61s

my $self = shift;
return (1, $self->msg('e5')) unless $self->priv >= 1;
my @out;

my $r = DXProt::get_pc11_61_stats();
#$DB::single = 1;
if ($r) {
	my $spots = $r->{pc61_rx} + $r->{pc11_rx};
	my $stats = sprintf "spots pc61: $r->{pc61_rx} pc11: $r->{pc11_rx}(%0.1f%%) total: $spots - promotions - by pc61: $r->{pc11_to_61} by route: $r->{rpc11_to_61} total: $r->{promotions}(%0.1f%%)", $r->{pc11_percent}, $r->{promotions_percent};
	push @out, $stats;
} else {
	push @out, qq{pc11 stats not available};
}
return (1, @out);
