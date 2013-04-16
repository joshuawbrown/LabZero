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

package LabZero::IncLocate;

use strict;
use Cwd qw(realpath);

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(inc_locate);


sub inc_locate {

	my ($target) = @_;

	my ($answer) = grep { -e "$_/$target" } @INC;
	
	if ($answer) {
		return realpath("$answer/$target");
	}
	
	return undef;
	
}

1; # It's a package
