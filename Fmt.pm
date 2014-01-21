###########################################################################
# Copyright 2012 Joshua Brown
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###########################################################################

package LabZero::Fmt;

use strict;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
	fmt_comma fmt_comma_zero fmt_elapsed
);


sub fmt_comma {

	my ($number) = @_;
	
	my $result = sprintf("\%0.0f", $number);
	while ($result =~ s/(\d)(\d\d\d)\b/$1,$2/) {}
	return $result;

}

sub fmt_comma_zero {

	my ($number, $placeholder) = @_;
	
	my $result = sprintf("\%0.0f", $number);
	while ($result =~ s/(\d)(\d\d\d)\b/$1,$2/) {}
	if ($result == 0) { return $placeholder; }
	return $result;

}

my %units = (
	yrs => 31449600,
	wks => 604800,
	days => 86400,
	hrs => 3600,
	min => 60,
);

my %long_units = (
	sec => 'seconds',
	yrs => 'years',
	wks => 'weeks',
	days => 'days',
	hrs => 'hours',
	min => 'minutes',
);

sub fmt_elapsed {
	
	# USAGE: print seconds_to_string($elapsed);
	
	my ($elapsed, $long) = @_;
	
	# First, decide the units
	
	my $mult = 1;
	my $unit = 'sec';
	
	foreach my $x (sort {$units{$b} <=> $units{$a}} keys %units) {
		if ($elapsed > $units{$x}) {
			$unit = $x;
			if ($long) { $unit = $long_units{$unit}; }
			$mult = $units{$x};
			last;
		}
	}

	my $total = $elapsed / $mult;
	my $int = int($total);
	my $fraction = $total - $int;
	my $output;
	
	if ($unit =~ m/(sec|min)/) { $output = "$int $unit"; }
	elsif ($fraction > 0.75) { $int +=1; $output = "Almost $int $unit"; }
	elsif ($fraction > 0.25) { $output = "Over $int $unit"; }
	else { $output = "$int $unit"; }
	
	if ($int == 1) { $output =~ s/s$//; }

	return $output;
	
}