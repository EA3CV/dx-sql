#
# Reload the SQL table 'bads' from the files: baddx, badnode, badspotter
#

my $self = shift;
my @out;
return (1, $self->msg('e5')) if $self->priv < 9;

require DXHash;
my $hash = DXHash->new("bads");
$hash->reload();

@out = ($self->msg('ok'));
return (1, @out);
