#!/usr/bin/perl

use strict;

use Time::Piece;
use JSON;
use Data::Dumper;

use LabZero::Fail;
use LabZero::Context;

use DataBank::Accounts;

my $days_1 = 86400;

my $context = LabZero::Context->load();
test_mongo($context->mongo);
test_mongo($context->mongo2);

sub test_mongo {

  my ($mong, $label) = @_;

  my $db = $_[0]->get_database('test');
  my $c = $db->get_collection('test');
  my $result = $c->count();
  print "Server $label> $result\n";
	flog($mong);


}
