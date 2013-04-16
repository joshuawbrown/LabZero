###########################################################################
# Copyright 2005 Lab-01 LLC <http://lab-01.com/>
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
#
# Tmojo(tm) is a trademark of Lab-01 LLC.
###########################################################################

package LabZero::Tmojo::ExpressionLanguageLib;

use strict;
use LabZero::Fail;

sub new {
	my ($class) = @_;
	
	return bless {}, $class;
}

sub tmojo_el_can {
	my ($self, $method_name) = @_;
	
	return 1; # tmojo el can always call the html helper
}

sub array {
	my ($self, @params) = @_;
	
	return \@params;
}

sub hash {
	my ($self, %params) = @_;
	
	return \%params;
}

sub substr {
	shift @_;
	
	if (@_ == 4) {
		return CORE::substr($_[0], $_[1], $_[2], $_[3]);
	}
	elsif (@_ == 3) {
		return CORE::substr($_[0], $_[1], $_[2]);
	}
	elsif (@_ == 2) {
		return CORE::substr($_[0], $_[1]);
	}
	else {
		freak("wrong number of arguments to substr");
	}
}

sub uc {
	shift @_;
	
	if (@_ == 1) {
		return CORE::uc($_[0]);
	}
	else {
		freak("wrong number of arguments to uc")
	}
}

sub lc {
	shift @_;
	
	if (@_ == 1) {
		return CORE::lc($_[0]);
	}
	else {
		freak("wrong number of arguments to lc")
	}
}

1;