#
# DXSpider - Cluster Synchronization Utility
#
# This module sends rcmds to other nodes in the cluster to request
# synchronization of data like bads, badip, badwords, etc.
#

package DXClusterSync;

use strict;
use warnings;
use DXDebug;
use DXProt;
use DXVars;
use Route::Node;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(broadcast_load );

# Params:
#   $type - the type of sync to perform: 'bads', 'badip', 'badwords', etc.
#
# Example:
#   sync_to_cluster('bads');
#

sub broadcast_load {
	my ($type) = @_;
	return unless $type;

	my $command = "load/$type";

	foreach my $target (@main::cluster_nodes) {
		next if uc($target) eq uc($main::mycall);  # skip our own node

		my $node = Route::Node::get($target);
		unless ($node) {
			dbg("[DXClusterSync] WARNING: Node '$target' not found in routing table");
			next;
		}

		DXProt::addrcmd(undef, $target, $command);
		dbg("[DXClusterSync] Sent rcmd '$command' to $target");
	}
}

1;
