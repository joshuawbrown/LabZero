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

package LabZero::Tmojo::NamespaceTemplateLoaderEnvelope;

use strict;
use base qw(LabZero::Tmojo::AbstractTemplateLoader);

sub new {
	my ($class) = @_;
		
	my $self = {
		sub_loaders => {},
	};
		
	return bless $self, $class;
}

sub add_namespace {
	my ($self, $namespace, $sub_loader) = @_;
		
	$self->{sub_loaders}{$namespace} = $sub_loader;
}

sub load_template {
	my ($self, $normalized_template_id, $cache_time_stamp) = @_;
	
	# STRIP OFF THE NAMESPACE
	my ($ns, $normalized_template_id) = $self->strip_namespace($normalized_template_id);
	
	# MAKE SURE IT EXISTS
	if (not defined $self->{sub_loaders}{$ns}) {
		die "couldn't find template namespace '$ns'";
	}
	
	# AND LET IT GO
	return $self->{sub_loaders}{$ns}->load_template($normalized_template_id, $cache_time_stamp);
}

sub template_exists {
	my ($self, $normalized_template_id) = @_;
	
	# STRIP OFF THE NAMESPACE
	my ($ns, $normalized_template_id) = $self->strip_namespace($normalized_template_id);
	
	# MAKE SURE IT EXISTS
	if (not defined $self->{sub_loaders}{$ns}) {
		return 0;
	}
	
	# AND LET IT GO
	return $self->{sub_loaders}{$ns}->template_exists($normalized_template_id);
}

sub is_dir {
	my ($self, $normalized_template_id) = @_;
	
	# STRIP OFF THE NAMESPACE
	my ($ns, $normalized_template_id) = $self->strip_namespace($normalized_template_id);
	
	# MAKE SURE IT EXISTS
	if (not defined $self->{sub_loaders}{$ns}) {
		return 0;
	}
	
	# AND LET IT GO
	return $self->{sub_loaders}{$ns}->is_dir($normalized_template_id);
}

sub template_mtime {
	my ($self, $normalized_template_id) = @_;
	
	# STRIP OFF THE NAMESPACE
	my ($ns, $normalized_template_id) = $self->strip_namespace($normalized_template_id);
	
	# MAKE SURE IT EXISTS
	if (not defined $self->{sub_loaders}{$ns}) {
		return 0;
	}
	
	# AND LET IT GO
	return $self->{sub_loaders}{$ns}->template_mtime($normalized_template_id);
}

1;