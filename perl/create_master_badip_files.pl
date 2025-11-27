#!/usr/bin/env perl
#
# Get the TOR exit and relay lists from the net, extract the exit and relay
# node ip addresses and store them, one per line, in the standard places
# in /spider/local_data. 
#

use 5.16.1;

# search local then perl directories
use strict;

BEGIN {
	# root of directory tree for this system
	our $root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

	mkdir "$root/local_data", 02777 unless -d "$root/local_data";

	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
	our $data = "$root/data";
}


use DXVars;
use SysVar;

use DXDebug;
use DXUtil;

use LWP::Simple;
use JSON;
use Date::Parse;
use File::Copy;
use DXUtil;

DXDebug::dbginit();

$ENV{PERL_JSON_BACKEND} = "JSON::XS,JSON::PP";


my $debug;

if (@ARGV && $ARGV[0] eq '-x') {
	shift;
	$debug = 1;
}
my $url = "https://onionoo.torproject.org/details";
my $relayfn = localdata('badip.torrelay');
my $exitfn = localdata('badip.torexit');

my $last_seen_window = 10800;
my $content;

if (@ARGV) {
	local $/ = undef;
	my $fn = shift;
	open IN, $fn or die "$0 cannot open file $fn, $!";
	$content = <IN>;
	close IN;
} else {
	$content = get($url) or die "$0: connect error on $url, $!\n";
}

die "No TOR content available $!\n" unless $content;

my $l = length $content;
my $data = decode_json($content);
my $now = time;
my $ecount = 0;
my $rcount = 0;
my $error = 0;

my $rand = rand;
open RELAY, ">$relayfn.$rand" or die "$0: cannot open $relayfn $!";
open EXIT, ">$exitfn.$rand" or die "$0: cannot open $exitfn $1";

foreach my $e (@{$data->{relays}}) {

	my $seen = str2time($e->{last_seen});
	next unless $seen >= $now - $last_seen_window;
	
	my @exit = clean_addr(@{$e->{exit_addresses}}) if exists $e->{exit_addresses} ;
	my @or = clean_addr(@{$e->{or_addresses}}) if exists $e->{or_addresses};
	my $ors = join ', ', @or;
	my $es = join ', ', @exit;
	dbg "$0: $e->{nickname} $e->{last_seen} relays: [$ors] exits: [$es]" if $debug;
	for (@exit) {
		if (is_ipaddr($_)) {
			print EXIT "$_\n";
			++$ecount;
		} else {
			print STDERR "$_\n";
			++$error;
		}
	}
	for (@or) {
		if (is_ipaddr($_)) {
			print RELAY "$_\n";
			++$rcount;
		} else {
			print STDERR "$_\n";
			++$error;
		}
	}
}

close RELAY;
close EXIT;

dbg("$0: $rcount relays $ecount exits $error error(s) found.");
move "$relayfn.$rand", $relayfn if $rcount;
move "$exitfn.$rand", $exitfn if $ecount;
unlink "$relayfn.$rand";
unlink "$exitfn.$rand";

exit $error;

my %addr;

sub clean_addr
{
	my @out;
	foreach (@_) {
		my ($ipv4) = /^((?:\d+\.){3}\d+)/;
		if ($ipv4) {
			next if exists $addr{$ipv4};
			push @out, $ipv4;
			$addr{$ipv4}++;
			next;
		}
		my ($ipv6) = /^\[([:a-f\d]+)\]/;
		if ($ipv6) {
			next if exists $addr{$ipv6};
			push @out, $ipv6;
			$addr{$ipv6}++;
		}
	}
	return @out;
}
