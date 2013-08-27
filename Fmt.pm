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
	fmt_comma fmt_comma_zero
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
