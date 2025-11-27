#
# Export the user database to ASCII (JSON per line) format
#
my $self = shift;
my $line = shift;

return (1, $self->msg('e5')) unless $self->priv >= 9;

use File::Copy;

$line ||= 'user_json';
my ($fn) = split /\s+/, $line;
$fn =~ s|[^a-zA-Z0-9_\-\.]|_|g;
$fn = "$main::local_data/$fn" unless $fn =~ m|/|;

# SOLO hacer rotate si el backend es mysql o sqlite
if ($main::db_backend ne 'file' && -e $fn) {
	move("$fn.oooo", "$fn.ooooo") if -e "$fn.oooo";
	move("$fn.ooo",  "$fn.oooo")  if -e "$fn.ooo";
	move("$fn.oo",   "$fn.ooo")   if -e "$fn.oo";
	move("$fn.o",    "$fn.oo")    if -e "$fn.o";
	move($fn,        "$fn.o");
}

my $msg = DXUser::export($fn);

return (1, $msg);
