###########################################################################
# Copyright 2004-2008 Lab-01 LLC <http://lab-01.com/>
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

package LabZero::Tmojo::AbstractTemplateLoader;

use strict;

=head2 Public Methods
=cut

sub load_template {
	my ($self, $normalized_template_id, $cache_time_stamp) = @_;
	
	die "public method not implemented: load_template";
}

sub template_exists {
	my ($self, $normalized_template_id) = @_;
	
	die "public method not implemented: template_exists";
}

sub is_dir {
	my ($self, $normalized_template_id) = @_;
	
	die "public method not implemented: is_dir";
}

sub template_mtime {
	my ($self, $normalized_template_id) = @_;
	
	die "public method not implemented: template_mtime";
}

sub strip_namespace {
	my ($self, $normalized_template_id) = @_;
	
	if ($normalized_template_id =~ m/^(\w*):(.+)/) {
		return ($1, $2);
	}
	else {
		return ('', $normalized_template_id);
	}
}

1;