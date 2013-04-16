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

package LabZero::Tmojo::TemplateLoader;

use strict;
use base qw(LabZero::Tmojo::NamespaceTemplateLoaderEnvelope);

use LabZero::Tmojo::FilesystemTemplateLoader;

sub new {
	my ($class, $template_dir) = @_;
	
	# USE THE BASE CONSTRUCTOR
	my $self = $class->SUPER::new();
	
	# ADD THE BLANK NAMESPACE
	$self->add_namespace('' => $template_dir);
	
	# AND WE'RE DONE
	return $self;
}

sub add_namespace {
	my ($self, $namespace, $template_dir, $restricted) = @_;
	
	if (ref($template_dir)) {
		$self->SUPER::add_namespace($namespace, $template_dir);
	}
	else {
		my $loader = LabZero::Tmojo::FilesystemTemplateLoader->new($template_dir)->set_restricted($restricted);
		$self->SUPER::add_namespace($namespace, $loader);
	}
}

1;