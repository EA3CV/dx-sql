#!/usr/bin/env perl
#
# Something to create my subset of the US call book data,
# in my flat file form, either from the main data base or
# else the daily updates. 
#
# You can get the main database from: 
#
#   https://data.fcc.gov/download/pub/uls/complete/l_amat.zip
#
# The daily data bases are available as a set of seven from here:-
#
#  https://data.fcc.gov/download/pub/uls/daily/l_am_sat.zip 
#  https://data.fcc.gov/download/pub/uls/daily/l_am_sun.zip 
#  https://data.fcc.gov/download/pub/uls/daily/l_am_mon.zip 
#  https://data.fcc.gov/download/pub/uls/daily/l_am_tue.zip 
#  https://data.fcc.gov/download/pub/uls/daily/l_am_wed.zip 
#  https://data.fcc.gov/download/pub/uls/daily/l_am_thu.zip 
#  https://data.fcc.gov/download/pub/uls/daily/l_am_fri.zip
# 
# this program expects one or more zip files containing the call book
# data as arguments.
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#
#
#

use strict;

# make sure that modules are searched in the order local then perl
BEGIN {
	# root of directory tree for this system
	use vars qw($root);
	
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

	mkdir "$root/local_data", 02777 unless -d "$root/local_data";

	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use SysVar;

use Archive::Zip qw(:ERROR_CODES);
use Archive::Zip::MemberRead;
use IO::File;
use Compress::Zlib;
use DXUtil;

my $blksize = 1024 * 1024;

STDOUT->autoflush(1);

my $dbrawfn = localdata("usdbraw.gz");

rename "$dbrawfn.oo", "$dbrawfn.ooo";
rename "$dbrawfn.o", "$dbrawfn.oo";
rename "$dbrawfn", "$dbrawfn.o";
my $gzfh = gzopen($dbrawfn, "wb") or die "Cannot open $dbrawfn $!";

my $ctycount;
  
foreach my $argv (@ARGV) {
	my $zip = new Archive::Zip($argv) or die "Cannot open $argv $!\n";
	print "Doing $argv\n";
	handleEN($zip, $argv);
	handleAM($zip, $argv);
	handleHS($zip, $argv);
}

$gzfh->gzclose;

exit(0);

sub handleEN
{
	my ($zip, $argv) = @_;
	my $mname = "EN.dat";
	my $ofn = localdata($mname);
	print "  Handling EN records, unzipping";
	if ($zip->extractMember($mname, $ofn) == AZ_OK) {
		my $fh = new IO::File "$ofn" or die "Cannot open $ofn $!";
		if ($fh) {
			
			print ", storing";
			
			my $count;
			my $buf;
			
			while (my $l = $fh->getline) {
				$l =~ s/[\r\n]+$//;
				my ($rt,$usi,$ulsfn,$ebfno,$call,$type,$lid,$name,$first,$middle,$last,$suffix,
					$phone,$fax,$email,$street,$city,$state,$zip,$pobox,$attl,$sgin,$frn) = split /\|/, $l;

#				print "ERR: $l\n" unless $call && $city && $state;

				if ($call && $city && $state) {
					my $rec = uc join '|', $call,$city,$state if $city && $state;
					$buf .= "$rec\n";
					if (length $buf > $blksize) {
						$gzfh->gzwrite($buf);
						undef $buf;
					}
					$count++;
				}
			}
			$gzfh->gzwrite($buf) if length $buf;
			print ", $count records\n";
			$fh->close;
		}
		unlink $ofn;
	} else {
		print "EN missing in $argv\n";
		return;
	}
}

sub handleAM
{

}

sub handleHS
{

}
