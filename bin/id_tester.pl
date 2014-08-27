#!/usr/bin/perl

use strict;

use LabZero::Context;

my $context = LabZero::Context->load();
my $couch = $context->couchdb();

for my $i (0..9) {

	my $id = $couch->next_id();
	print "[$i] $id\n";

}