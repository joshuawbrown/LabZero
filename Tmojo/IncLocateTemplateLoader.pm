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

package LabZero::Tmojo::IncLocateTemplateLoader;

use strict;
use base qw(LabZero::Tmojo::AbstractTemplateLoader);

use LabZero::IncLocate;

sub new {
	my ($class) = @_;
		
	# THERE'S NOT MUCH TO THIS
	return bless {}, $class;
}

sub check_namespace {
	my ($self, $normalized_template_id) = @_;
	
	my ($ns) = $self->strip_namespace($normalized_template_id);
	
	if ($ns ne '') {
		die "LabZero::Tmojo::IncLocateTemplateLoader doesn't support namespaces";
	}
}

sub load_template {
	my ($self, $normalized_template_id, $cache_time_stamp) = @_;
	
	# CHECK TO MAKE SURE WE DON'T HAVE A NAMESPACE
	$self->check_namespace($normalized_template_id);
	
	# MAKE SURE THE FILE NAME ENDS WITH .tmo
	if (substr($normalized_template_id, -4) ne '.tmo') {
		die "invalid template id '$normalized_template_id'";
	}
	
	my $file_name = inc_locate(substr($normalized_template_id, 1));
	
	if (not defined $file_name) {
		die "couldn't find template '$normalized_template_id' in \@INC";
	}
	
	unless (-r $file_name) {
		die "can't read template '$normalized_template_id' ($file_name)";
	}
	
	if (-d $file_name) {
		die "template '$normalized_template_id' ($file_name) is a directory";
	}
	
	my $source_time_stamp = (stat($file_name))[9];
		
	if ($source_time_stamp >= $cache_time_stamp) {
		# LOAD AND RETURN THE FILE
		open my ($fh), $file_name;
		# binmode($fh, ':utf8');
		local $/ = "\n"; # THIS CAN GET EXTRA SCREWED UP IN MOD_PERL
		my @template_lines = <$fh>;
		close $fh;
		
		return (0, \@template_lines, 0);
	}
	else {
		return (1);
	}
}

sub template_exists {
	my ($self, $normalized_template_id) = @_;
	
	# CHECK TO MAKE SURE WE DON'T HAVE A NAMESPACE
	$self->check_namespace($normalized_template_id);
	
	my $file_name = inc_locate(substr($normalized_template_id, 1));
	
	if (defined $file_name and -r $file_name and substr($file_name, -4) eq '.tmo') {
		return 1;
	}
	else {
		return 0;
	}
}

sub is_dir {
	my ($self, $normalized_template_id) = @_;
	
	# CHECK TO MAKE SURE WE DON'T HAVE A NAMESPACE
	$self->check_namespace($normalized_template_id);
	
	my $file_name = inc_locate(substr($normalized_template_id, 1));
	
	if (-d $file_name) {
		return 1;
	}
	else {
		return 0;
	}
}

sub template_mtime {
	my ($self, $normalized_template_id) = @_;
	
	# CHECK TO MAKE SURE WE DON'T HAVE A NAMESPACE
	$self->check_namespace($normalized_template_id);
	
	my $file_name = inc_locate(substr($normalized_template_id, 1));
	
	if (defined $file_name and -r $file_name and substr($file_name, -4) eq '.tmo') {
		return (stat($file_name))[9];
	}
	else {
		return 0;
	}
}

1;
