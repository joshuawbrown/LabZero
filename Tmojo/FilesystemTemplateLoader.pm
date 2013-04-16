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

package LabZero::Tmojo::FilesystemTemplateLoader;

use strict;
use base qw(LabZero::Tmojo::AbstractTemplateLoader);

use Cwd qw(realpath);
use Encode;

use LabZero::Fail;

sub new {
	my ($class, $template_dir) = @_;
	
	# STRIP OFF TRAILING SLASH
	$template_dir =~ s/\/$//;
	
	# MAKE SURE THE DIRECTORY EXISTS
	if (not -d $template_dir) {
		fail("'$template_dir' does not exist or is not a directory");
	}
	
	# SET OURSELVES UP
	my $self = {
		template_dir => realpath($template_dir),		
		restricted => 0,
	};
	
	# AND WE'RE DONE
	return bless $self, $class;
}

sub set_restricted {
	my ($self, $restricted) = @_;
	
	$self->{restricted} = $restricted ? 1 : 0;
	
	return $self;
}

sub check_namespace {
	my ($self, $normalized_template_id) = @_;
	
	my ($ns) = $self->strip_namespace($normalized_template_id);
	
	if ($ns ne '') {
		fail("LabZero::Tmojo::FilesystemTemplateLoader doesn't support namespaces");
	}
}

sub load_template {
	my ($self, $normalized_template_id, $cache_time_stamp) = @_;
	
	# CHECK TO MAKE SURE WE DON'T HAVE A NAMESPACE
	$self->check_namespace($normalized_template_id);
	
	my $file_name = "$self->{template_dir}$normalized_template_id";
	
	unless (-r $file_name) {
		fail("couldn't find template '$normalized_template_id' ($file_name)");
	}
	
	if (-d $file_name) {
		fail("template '$normalized_template_id' ($file_name) is a directory");
	}
	
	my $source_time_stamp = (stat($file_name))[9];
		
	if ($source_time_stamp != $cache_time_stamp) {
		# LOAD AND RETURN THE FILE
		open my ($fh), $file_name;
		# binmode($fh, ':utf8');
		local $/ = "\n"; # THIS CAN GET EXTRA SCREWED UP IN MOD_PERL
		my @template_lines = <$fh>;
		close $fh;
		
		my @decoded_lines = map { decode('utf8', $_) } @template_lines;
		
		return (0, \@decoded_lines, $self->{restricted}, $source_time_stamp);
	}
	else {
		return (1);
	}
}

sub template_exists {
	my ($self, $normalized_template_id) = @_;
	
	# CHECK TO MAKE SURE WE DON'T HAVE A NAMESPACE
	$self->check_namespace($normalized_template_id);
	
	my $file_name = "$self->{template_dir}$normalized_template_id";
	
	if (-r $file_name) {
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
	
	my $file_name = "$self->{template_dir}$normalized_template_id";
	
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
	
	my $file_name = "$self->{template_dir}$normalized_template_id";
	
	if (-r $file_name) {
		return (stat($file_name))[9];
	}
	else {
		return 0;
	}
}

1;
