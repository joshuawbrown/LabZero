#!/usr/bin/perl

use strict;

use LabZero::Context;

my $context = LabZero::Context->load();

my $glog = $context->glog('test/myglog');

$glog->event(TEST => 'this is a test');

my $sql = $context->mysql();