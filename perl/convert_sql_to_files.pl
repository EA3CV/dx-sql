#
# Internal DXSpider command to export badwords, badips, and bads from SQL backend
#

my $self = shift;
my $line = shift;

return (1, $self->msg('e5')) unless $self->priv >= 9;

use Encode;
use DXVars;
use DBI;

my $basedir = $main::local_data;
my $backend = $main::db_backend;
my @out;

push @out, "Starting SQL-to-file conversion (backend: $backend)...";

# Crear conexión directa
my $dbh;
if ($backend eq 'mysql') {
    $dbh = DBI->connect(
        "DBI:mysql:database=$main::mysql_db;host=$main::mysql_host",
        $main::mysql_user, $main::mysql_pass,
        { RaiseError => 1, AutoCommit => 1, mysql_enable_utf8mb4 => 1 }
    );
} elsif ($backend eq 'sqlite') {
    $dbh = DBI->connect(
        $main::sqlite_dsn, $main::sqlite_dbuser, $main::sqlite_dbpass,
        { RaiseError => 1, AutoCommit => 1, sqlite_unicode => 1 }
    );
} else {
    return (0, "[ERROR] Unsupported backend: $backend");
}

unless ($dbh) {
    return (0, "[ERROR] Cannot connect to SQL database");
}

# Exportar badwords
push @out, "Exporting badwords...";
my $bw_file = "$basedir/badword.new";
open my $bw_fh, '>:encoding(UTF-8)', $bw_file or return (0, "Cannot open $bw_file: $!");
my $bw_sth = $dbh->prepare("SELECT word FROM badwords ORDER BY word");
$bw_sth->execute();
while (my ($word) = $bw_sth->fetchrow_array) {
    next unless defined $word && $word ne '';
    print $bw_fh "$word\n";
}
close $bw_fh;

# Exportar badips
push @out, "Exporting bad IP lists...";
my $bi_sth = $dbh->prepare("SELECT ip, list_type FROM badips ORDER BY list_type, ip");
$bi_sth->execute();
my %badip_lists;
while (my ($ip, $type) = $bi_sth->fetchrow_array) {
    next unless $ip && $type;
    push @{ $badip_lists{$type} }, $ip;
}
foreach my $type (sort keys %badip_lists) {
    my $file = "$basedir/$type";
    open my $fh, '>:encoding(UTF-8)', $file or return (0, "Cannot open $file: $!");
    print $fh "$_\n" for @{ $badip_lists{$type} };
    close $fh;
}

# Exportar bads (baddx, badspotter, badnode)
push @out, "Exporting bads lists...";
my $bads_sth = $dbh->prepare("SELECT list_name, callsign, timestamp FROM bads ORDER BY list_name, callsign");
$bads_sth->execute();
my %bads_lists;
while (my ($list, $call, $ts) = $bads_sth->fetchrow_array) {
    $bads_lists{$list}{$call} = $ts;
}
foreach my $list (sort keys %bads_lists) {
    my $file = "$basedir/$list";
    open my $fh, '>:encoding(UTF-8)', $file or return (0, "Cannot open $file: $!");
    print $fh "bless( {\n";
    foreach my $call (sort keys %{ $bads_lists{$list} }) {
        printf $fh "  %-12s => %s,\n", "'$call'", $bads_lists{$list}{$call};
    }
    print $fh "  name => '$list'\n";
    print $fh "} , 'DXHash' )\n";
    close $fh;
}

# Exportar filtros
push @out, "Exporting filters...";
my $filters_sth = $dbh->prepare("SELECT list_name, sort, filter_key, rule_type, user_expr, asc_expr FROM filters ORDER BY list_name, sort, filter_key, rule_type");
$filters_sth->execute();

my %filters;
while (my ($list_name, $sort, $filter_key, $rule_type, $user, $asc) = $filters_sth->fetchrow_array) {
    $filters{$sort}{$list_name}{$filter_key}{$rule_type} = {
        user => $user,
        asc  => $asc,
        code => undef,
    };
    $filters{$sort}{$list_name}{name} = $list_name;
    $filters{$sort}{$list_name}{sort} = $sort;
}

my $json = DXJSON->new->indent(1);

foreach my $sort (keys %filters) {
    my $dir = "$main::root/filter/$sort";
    mkdir $dir unless -d $dir;

    foreach my $list_name (keys %{ $filters{$sort} }) {
        my $filepath = "$dir/$list_name";
        open my $fh, '>:encoding(UTF-8)', $filepath or return (0, "Cannot open $filepath: $!");

        # Limpiar estructura para guardar solo claves válidas
        my %data;
        foreach my $k (keys %{ $filters{$sort}{$list_name} }) {
            next if $k eq 'name' || $k eq 'sort';
            $data{$k} = $filters{$sort}{$list_name}{$k};
        }

        $data{name} = $list_name;
        $data{sort} = $sort;

        print $fh $json->encode(\%data);
        close $fh;
    }
}

push @out, "Conversion complete.";
return (1, @out);
