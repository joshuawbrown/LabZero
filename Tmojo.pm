###########################################################################
# Copyright 2003, 2004, 2005, 2008 Lab-01 LLC <http://lab-01.com/>
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

package LabZero::Tmojo;

our $VERSION = '0.700';

=head1 NAME

LabZero::Tmojo - Dynamic Text Generation Engine

=head1 SYNOPSIS

  my $tmojo = LabZero::Tmojo->new(
    template_dir => '/location/of/templates',
  );
  
  my $result = $tmojo->call('my_template.tmojo', arg1 => 1, arg2 => 3);
  
  # HONESTLY, THIS SYNOPSIS DOESN'T COVER NEARLY ENOUGH.
  # GO READ TMOJO IN A NUTSHELL

=head1 ABSTRACT

Tmojo is used for generating dynamic text documents.
While it is particularly suited to generating HTML
and XML documents, it can be used effectively to
produce any text output, including dynamically
generated source code.

=head1 AUTHOR

Will Conant <will@lab-01.com>

=cut

use strict;
use Data::Dumper;
use Symbol qw(delete_package);

use LabZero::Fail;
use LabZero::Tmojo::TemplateLoader;
use LabZero::Tmojo::ExpressionLanguage;

our $LAST_TEMPLATE_PACKAGE_INDEX = 0;

sub new {
	my ($class, %args) = @_;

	if (defined $args{template_dir}) {
		$args{template_loader} = LabZero::Tmojo::TemplateLoader->new($args{template_dir});
		delete $args{template_dir};
	}
	elsif (not defined $args{template_loader}) {
		$args{template_loader} = LabZero::Tmojo::TemplateLoader->new($ENV{TMOJO_TEMPLATE_DIR});
	}
	
	%args = (
		context_path => '',
		
		last_compile_times => {},
		template_packages => {},
		
		%args,
	);
	
	if ($args{glog} and $args{context_path} eq '') {
		my (undef, $filename, $line) = caller(0);
		$args{glog}->event('TMOJO_CREATED' => "$$ " . ref($args{template_loader}) . " $filename line $line");
	}
	
	return bless \%args, $class;
}

sub tmojo_el_can {
	my ($self, $method_name) = @_;
	
	return grep { $_ eq $method_name } qw(
		prepare
		call
		template_exists
		is_dir
		template_mtime
	);
}

sub prepare {
	my ($self, $template_id, %args) = @_;	
	
	# HANDLE RESERVED ARGUMENTS
	my $suggested_container_id;
	my $container_override_id;
	my $explicit_next = undef;
	my $explicit_args = \%args;
	
	foreach my $key (keys %args) {
		if ($key eq '-container') {
			$suggested_container_id = delete $args{$key};
		}
		elsif ($key eq '-container_override') {
			$container_override_id = delete $args{$key};
		}
		elsif ($key eq '-next') {
			$explicit_next = delete $args{$key};
		}
		elsif ($key eq '-args') {
			$explicit_args = delete $args{$key};
		}
		elsif (substr($key, 0, 1) eq '-') {
			freak("reserved parameter name $key");
		}
	}
	
	my $current_package = $self->get_template_class($template_id);
	my $current_template = $current_package->new($explicit_args, $explicit_next);
	
	# WE HAVE TO KEEP TRACK OF WHICH CONTAINERS HAVE BEEN USED,
	# SO THAT USERS CAN'T CREATE AN INFINITE CONTAINER LOOP
	my %used_containers = (
		$self->normalize_template_id($template_id) => 1,
	);
	
	for (;;) {
		no strict 'refs';
		
		my $contextual_tmojo = ${$current_package . '::Tmojo'};
		
		# DECIDE ON WHAT CONTAINER WE ACTUALLY WILL USE
		my $container_id = '';
		
		if (defined $container_override_id) {
			$container_id = $container_override_id;
		}
		elsif (defined $current_template->{init}{container}) {
			# THIS ALLOWS THE CONTAINER TO BE SET DURING THE INIT PHASE
			$container_id = $current_template->{init}{container};
		}
		elsif (defined ${$current_package . '::TMOJO_CONTAINER'}) {
			# ASK THE TEMPLATE PACKAGE WHAT CONTAINER IT LIKES
			$container_id = ${$current_package . '::TMOJO_CONTAINER'};
		}
		elsif (defined $suggested_container_id) {
			# AT VERY LAST, WE'LL GO FOR WHATEVER WAS PASSED INTO '-container'
			$container_id = $suggested_container_id;
		}
		
		# WE'LL ONLY USE THESE ON THE FIRST PASS
		$suggested_container_id = undef;
		$container_override_id = undef;
		
		if ($container_id ne '') {
			# NORMALIZE THE CONTAINER ID FOR GOOD MEASURE
			$container_id = $contextual_tmojo->normalize_template_id($container_id);
			
			# CHECK TO MAKE SURE THAT THE CONTAINER HASN'T ALREADY BEEN USED
			if (defined $used_containers{$container_id}) {
				fail("circular container reference, $container_id already used (this will cause an infinite loop)");
			}
			
			# PUT IT IN THE USED LIST
			$used_containers{$container_id} = 1;
			
			# MOVE ON UP
			$current_package = $contextual_tmojo->get_template_class($container_id);
			$current_template = $current_package->new($explicit_args, $current_template);
		}
		else {
			return $current_template;
		}
	}
}

sub call {
	my ($self, $template_id, %args) = @_;	
	
	# PREPARE THE TEMPLATE
	my $template = $self->prepare($template_id, %args);

	# CALL MAIN
	return $template->main();
}

sub call_with_container {
	my ($self, $template_id, $container_override_id, %args) = @_;
	
	$self->call($template_id, %args, '-container_override' => $container_override_id);
}

sub template_exists {
	my ($self, $template_id) = @_;
	
	$template_id = $self->normalize_template_id($template_id);
	return $self->{template_loader}->template_exists($template_id);	
}

sub is_dir {
	my ($self, $template_id) = @_;
	
	$template_id = $self->normalize_template_id($template_id);
	return $self->{template_loader}->is_dir($template_id);	
}

sub template_mtime {
	my ($self, $template_id) = @_;
	
	$template_id = $self->normalize_template_id($template_id);
	return $self->{template_loader}->template_mtime($template_id);
}

sub parse_template {
	my ($source) = @_;
	
	my @parsed;
	
	my $tag_open  = "<:";
	my $tag_close = ":>";
	my $tag_line  = ":";
	
	my $tag_open_r;
	my $tag_close_r;
	my $tag_line_r;
	
	my $make_regexes = sub {
		$tag_open_r  = $tag_open;
		$tag_close_r = $tag_close;
		$tag_line_r  = $tag_line;
		
		$tag_open_r  =~ s/([\[\]\{\}\(\)\$\@\^\\\|\?\*\+])/\\$1/g;
		$tag_close_r =~ s/([\[\]\{\}\(\)\$\@\^\\\|\?\*\+])/\\$1/g;
		$tag_line_r  =~ s/([\[\]\{\}\(\)\$\@\^\\\|\?\*\+])/\\$1/g;
	};
	
	my $count_newlines = sub {
		my $count = 0;
		my $pos   = 0;
		
		while ($pos > -1) {
			$pos = index($_[0], "\n", $pos);
			if ($pos > -1) {
				$pos += 1;
				$count += 1;
			}
		}
		
		return $count;
	};
	
	$make_regexes->();
	
	my $keywords = join('|', qw(
		GLOBAL
		INIT
		METHOD
		PERL
		MERGE_PERL
		CAPTURE_PERL
		FILTER_PERL
		REGEX
		NOP
		TAG_STYLE
		MERGE
		EXEC
		SET
		IF
		ELSIF
		ELSE
		WHILE
		FOREACH
		END
		CAPTURE
		FILTER
		ISA
		CONTAINER
		RETURN
	));
	
	my %crush_defaults = (
		'GLOBAL'     => [0, 0],
		'/GLOBAL'    => [0, 2],
		
		'INIT'       => [0, 0],
		'/INIT'      => [0, 2],
		
		'METHOD'     => [0, 2],
		'/METHOD'    => [2, 2],
		
		'PERL'       => [1, 0],
		'/PERL'      => [0, 0],
		
		'MERGE_PERL' => [0, 0],
		
		'CAPTURE_PERL'    => [1, 2],
		'/CAPTURE_PERL'   => [2, 0],
		
		'FILTER_PERL'     => [0, 0],
		'/FILTER_PERL'    => [0, 0],
		
		'REGEX'      => [0, 0],
		'/REGEX'     => [0, 0],
		
		'TAG_STYLE'  => [1, 0],
		
		'NOP'        => [0, 0],
		
		'MERGE'      => [0, 0],
		'EXEC'       => [1, 0],
		'SET'        => [1, 0],
		'RETURN'     => [1, 0],
		
		'IF'         => [1, 0],
		'ELSIF'      => [1, 0],
		'ELSE'       => [1, 0],
		'WHILE'      => [1, 0],
		'FOREACH'    => [1, 0],
		'END'        => [1, 0],
		
		'CAPTURE'    => [1, 2],
		'/CAPTURE'   => [2, 0],
		
		'FILTER'     => [0, 0],
		'/FILTER'    => [0, 0],
		
		'ISA'        => [1, 0],
		'CONTAINER'  => [1, 0],
	);
	
	my $current_line = 1;

	while ($source ne '') {
	
		# SNAG THE NEXT TAG
		# -------------------
		
		my $found_tag = 0;
		my $tag_notation;
		my $pre_tag_text;

		if (scalar(@parsed) == 0) {
			if ($source =~ s/^([ \t]*)$tag_line_r//s) {
				$found_tag = 1;
				$tag_notation = 'line';
				$pre_tag_text = $1;
			}
		}
		
		unless ($found_tag == 1) {
			if ($source =~ s/^(.*?)($tag_open_r|(\n[ \t]*)$tag_line_r)//s) {
				$found_tag = 1;
				
				# DETERMINE IF THIS IS A LINE OR INLINE TAG
				if ($2 eq $tag_open) {
					$tag_notation = 'inline';
				}
				else {
					$tag_notation = 'line';
				}
				
				# DETERMINE THE PRE TAG TEXT
				$pre_tag_text = $1;
				if ($tag_notation eq 'line') {
					$pre_tag_text .= $3;
				}
			}
		}
		
		if ($found_tag == 1) {
				
			if ($pre_tag_text ne '') {
				# PUSH PLAIN TEXT ONTO THE PARSED RESULT
				push @parsed, { type => 'TEXT', text => $pre_tag_text, source => $pre_tag_text, crush_before => 0, crush_after => 0, start_line => $current_line };
				
				# COUNT THE NUMBER OF NEWLINES
				$current_line += $count_newlines->($pre_tag_text);
			}
			
			# GRAB THE REST OF THE TAG
			my $tag_source;
			my $tag_inside;
			
			if ($tag_notation eq 'inline') {
				$tag_source = $tag_line;
				
				if ($source =~ s/^(.*?)$tag_close_r//s) {
					$tag_inside = $1;
					$tag_source .= "$1$tag_close";
				}
				else {
					die "expected '$tag_close' in $source";
				}
			}
			else {
				$tag_source = $tag_open;
				
				# GOBBLE UP THE REST OF THE LINE
				$source =~ s/^([^\n]*)//;
				$tag_inside = $1;
				$tag_source .= $1;
			}
			
			# NOTCH UP THE LINES
			$current_line += $count_newlines->($tag_source);
			
			# PARSE THE TAG INSIDES
			
			my %tag = (
				source       => $tag_source,
				start_line   => $current_line,
			);
			
			# LOOK FOR WHITESPACE CRUSHERS
			
			if ($tag_notation eq 'inline') {
				if ($tag_inside =~ s/^--//) {
					$tag{crush_before} = 2;
				}
				elsif ($tag_inside =~ s/^-//) {
					$tag{crush_before} = 1;
				}
				elsif ($tag_inside =~ s/^\+//) {
					$tag{crush_before} = 0;
				}
				
				if ($tag_inside =~ s/--$//) {
					$tag{crush_after} = 2;
				}
				elsif ($tag_inside =~ s/-$//) {
					$tag{crush_after} = 1;
				}
				elsif ($tag_inside =~ s/\+$//) {
					$tag{crush_after} = 0;
				}
			}
			
			# FIGURE OUT THE TAG TYPE
			
			if ($tag_inside =~ /^\s*$/) {
				$tag{type} = 'NOP';
			}
			elsif ($tag_inside =~ s/^\s*(\/?(?:$keywords))(?:\s+|$)//) {
				$tag{type} = $1;
			}
			elsif ($tag_notation eq 'inline') {
				# USE A LITTLE MAGIC TO SEE IF WE'VE GOT A STATEMENT OR AN EXPRESSION
				if ($tag_inside =~ /^\s*(if|unless|while|until|for|foreach)\s+/) {
					 # THIS LOOKS LIKE A PERL STATEMENT
					 $tag{type} = 'PERL';
				}
				elsif ($tag_inside =~ /^\s*\}?\s*(else|elsif|continue)\s+/) {
					# THIS LOOKS LIKE A PERL STATEMENT
					$tag{type} = 'PERL';
				}
				elsif ($tag_inside =~ /^\s*\}\s*$/) {
					# THIS LOOKS LIKE A PERL STATEMENT
					$tag{type} = 'PERL';
				}
				else {
					# MUST BE A PERL EXPRESSION
					$tag{type} = 'MERGE_PERL';
				}
			}
			else {
				$tag{type} = 'PERL';
			}
			
			# PUT WHAT'S LEFT IN THE TAG TEXT
			
			$tag_inside =~ s/(^\s+|\s+$)//g;
			$tag{text} = $tag_inside;
			
			# SET DEFAULT CRUSHING
			
			if (not defined $tag{crush_before}) {
				$tag{crush_before} = $crush_defaults{$tag{type}}[0];
			}
			
			if (not defined $tag{crush_after}) {
				$tag{crush_after} = $crush_defaults{$tag{type}}[1];
			}
			
			
			# HANDLE FIRST-PASS TAGS
			# ----------------------
			if ($tag{type} eq 'TAG_STYLE') {
				if ($tag{text} eq 'default') {
					($tag_open, $tag_close, $tag_line) = ('<:', ':>', ':');
				}
				else {
					($tag_open, $tag_close, $tag_line) = split /\s+/, $tag{text};
				}
				
				if ($tag_open eq '') {
					die "invalid open tag marker";
				}
				
				if ($tag_close eq '') {
					die "invalid close tag marker";
				}
				
				if ($tag_line eq '') {
					die "invalid line tag marker";
				}
				
				if ($tag_line eq $tag_open or $tag_line eq $tag_close) {
					die "line tag marker must not be the same as either the open tag marker or close tag marker";
				}
				
				$make_regexes->();
			}
			
			# PUSH THE TAG ONTO THE RESULT
			
			push @parsed, \%tag;
		}
		elsif ($source ne '') {
			push @parsed, { type => 'TEXT', text => $source, source => $source, crush_before => 0, crush_after => 0, start_line => $current_line };
			$source = '';
		}
	}
	
	# RUN THROUGH AGAIN AND CRUSH WHITESPACE
	for (my $i = 0; $i < scalar(@parsed); $i++) {
		if ($parsed[$i]{crush_before} == 1 and $i > 0 and $parsed[$i-1]{type} eq 'TEXT') {
			$parsed[$i-1]{text} =~ s/\n?[ \t]*$//;
		}
		elsif ($parsed[$i]{crush_before} == 2 and $i > 0 and $parsed[$i-1]{type} eq 'TEXT') {
			$parsed[$i-1]{text} =~ s/\s+$//;
		}
		
		if ($parsed[$i]{crush_after} == 1 and $i < (scalar(@parsed)-1) and $parsed[$i+1]{type} eq 'TEXT') {
			$parsed[$i+1]{text} =~ s/^[ \t]*\n?//;
		}
		elsif ($parsed[$i]{crush_after} == 2 and $i < (scalar(@parsed)-1) and $parsed[$i+1]{type} eq 'TEXT') {
			$parsed[$i+1]{text} =~ s/^\s+//;
		}
	}
	
	# AND WE'RE DONE
	return \@parsed;
}

sub compile_template {
	my ($source, $template_id, $package_name, $restricted) = @_;
	
	# ADJUST FOR SOURCE LINES
	if (ref($source) eq 'ARRAY') {
		$source = join "", @$source;
	}
	
	# PARSE THE SOURCE INTO TAGS
	my $tags = parse_template($source);
	
	# INITIALIZE OUR PARSE VARIABLES
	my $global_section = '';
	
	my %methods = (
		main => '',
	);
	
	my %method_start_lines = (
		main => 1,
	);
	
	my $cur_method = 'main';
	
	my @stack;
	my @stack_details;
	my @stack_lines;
	
	# DEFINE A USEFUL LITTLE FUNCTION
	my $format_perl = sub {
		my ($source, $start_line) = @_;
		
		my @lines = split /\n/, $source;
		
		my $result = "\n#line $start_line TMOJO($template_id)\n";
		foreach my $line (@lines) {
			$result .= "$line\n";
		}
		
		return $result;
	};
	
	# PARSE ALL OF THE TAGS
	while (my $tag = shift @$tags) {
	
		# TEXT TAG
		# ---------------------------------
	
		if ($tag->{type} eq 'TEXT') {
			if ($tag->{text} ne '') {
				my $dumper = Data::Dumper->new([$tag->{text}]);
				$dumper->Useqq(1);
				$dumper->Indent(0);
				$dumper->Terse(1);
				my $literal = $dumper->Dump();
				
				$methods{$cur_method} .= "\t\$Result .= $literal;\n";
			}
		}
		
		# GLOBAL TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'GLOBAL') {
			
			if ($restricted) {
				die "cannot use GLOBAL tag in restricted template '$template_id' starting at line $tag->{start_line}";
			}
			
			if ($cur_method ne 'main') {
				die "cannot declare GLOBAL here in $template_id starting at line $tag->{start_line}";
			}
			
			if ($global_section ne '') {
				die "attempting to redefine GLOBAL section in $template_id starting at line $tag->{start_line}";
			}
			
			my $source = '';
			my $start_line;
			
			while (my $tag = shift @$tags) {
				if (not defined $tag) {
					die "missing /GLOBAL tag in $template_id";
				}
				
				if ($tag->{type} eq '/GLOBAL') {
					last;
				}
				elsif ($tag->{type} ne 'TEXT') {
					die "non-text tag in GLOBAL section in $template_id starting at line $tag->{start_line}";
				}
				else {
					if (not defined $start_line) {
						$start_line = $tag->{start_line};
					}
					$source .= $tag->{source};
				}
			}
			
			$global_section .= $format_perl->($source, $start_line);
		}
		
		# ISA TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'ISA') {
			
			if ($cur_method ne 'main') {
				die "cannot declare ISA here in $template_id starting at line $tag->{start_line}";
			}
			
			my $dumper = Data::Dumper->new([$tag->{text}]);
			$dumper->Useqq(1);
			$dumper->Indent(0);
			$dumper->Terse(1);
			my $isa_literal = $dumper->Dump();
			
			my $code = "our \@TMOJO_ISA;\npush \@TMOJO_ISA, $isa_literal;\n";
			
			$global_section .= $format_perl->($code, $tag->{start_line});
		}
		
		# CONTAINER TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'CONTAINER') {
			
			if ($cur_method ne 'main') {
				die "cannot declare CONTAINER here in $template_id starting at line $tag->{start_line}";
			}
			
			my $dumper = Data::Dumper->new([$tag->{text}]);
			$dumper->Useqq(1);
			$dumper->Indent(0);
			$dumper->Terse(1);
			my $container_literal = $dumper->Dump();
						
			my $code = "our \$TMOJO_CONTAINER = $container_literal;\n";
			
			$global_section .= $format_perl->($code, $tag->{start_line});
		}
		
		# INIT TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'INIT') {
			
			if ($cur_method ne 'main') {
				die "cannot declare INIT here in $template_id starting at line $tag->{start_line}";
			}
			
			if (defined $methods{'init'}) {
				die "attempting to redefine INIT section in $template_id starting at line $tag->{start_line}";
			}
			
			# GRAB ALL OF THE TAGS IN THE INIT SECTION
			my @init_tags;
			my $all_text = 1;
			while (my $tag = shift @$tags) {
				if (not defined $tag) {
					die "missing /INIT tag in $template_id";
				}
				
				push @init_tags, $tag;
				
				if ($tag->{type} eq '/INIT') {
					last;
				}
				elsif ($tag->{type} ne 'TEXT') {
					$all_text = 0;
				}
			}
			
			# IF THIS IS ALL TEXT, IT'S JUST SUPPOSED TO BE PERL
			if ($all_text and not $restricted) {
				# THIS IS AN OLD-SCHOOL INIT BLOCK
				my $source = '';
				my $start_line;
				
				while (my $tag = shift @init_tags) {					
					if ($tag->{type} eq '/INIT') {
						last;
					}
					else {
						if (not defined $start_line) {
							$start_line = $tag->{start_line};
						}
						$source .= $tag->{source};
					}
				}
				
				$methods{'init'} .= $format_perl->($source, $start_line);
			}
			else {
				# OTHERWISE, WE'LL ACT LIKE A METHOD
				unshift @$tags, @init_tags;
				$cur_method = 'init';
				
				# MAKE SURE THE METHOD IS CREATED
				$methods{$cur_method} = '';
			}
			
		}
		
		# /INIT TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq '/INIT') {
			
			if ($cur_method ne 'init') {
				die "cannot end INIT here in $template_id starting at line $tag->{start_line}";
			}
			
			$cur_method = 'main';
		}
		
		# PERL TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'PERL') {
			
			if ($restricted) {
				die "cannot use PERL tag in restricted template '$template_id' starting at line $tag->{start_line}";
			}
			
			if ($tag->{text} ne '') {
				my @lines = split /\n/, $tag->{text};
			
				my $cur_line = $tag->{start_line};
				while ($_ = shift @lines) {
					$methods{$cur_method} .= $format_perl->($_, $cur_line);
					$cur_line += 1;
				}
			}
			else {
				my $source = '';
				my $start_line;
				
				while (my $tag = shift @$tags) {
					if (not defined $tag) {
						die "missing /PERL tag in $template_id";
					}
					
					if ($tag->{type} eq '/PERL') {
						last;
					}
					elsif ($tag->{type} ne 'TEXT') {
						die "non-text tag in PERL section in $template_id starting at line $tag->{start_line}";
					}
					else {
						if (not defined $start_line) {
							$start_line = $tag->{start_line};
						}
						$source .= $tag->{source};
					}
				}
				
				$methods{$cur_method} .= $format_perl->($source, $start_line);
			}
		}
		
		# METHOD TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'METHOD') {
			
			if ($cur_method ne 'main') {
				die "cannot declare METHOD here in $template_id starting at line $tag->{start_line}";
			}
			
			$cur_method = $tag->{text};
			if ($cur_method !~ /^[a-zA-Z]\w*$/) {
				die "illegal method name '$cur_method' in $template_id starting at line $tag->{start_line}";
			}
			
			if ($cur_method eq 'init') {
				die "attempting to define init method with METHOD tag in $template_id starting at line $tag->{start_line}";
			}
			
			if ($cur_method eq 'new' or $cur_method eq 'tmojo' or $cur_method eq 'template_id') {
				die "method name $cur_method is reserved in $template_id starting at line $tag->{start_line}";
			}
			
			if (defined $methods{$cur_method}) {
				die "attempting to redefine METHOD '$cur_method' in $template_id starting at line $tag->{start_line}";
			}
			
			# MAKE SURE THE METHOD IS CREATED
			$methods{$cur_method} = '';
			$method_start_lines{$cur_method} = $tag->{start_line};
		}
		
		# /METHOD TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq '/METHOD') {
			
			if ($cur_method eq 'main' or $cur_method eq 'init') {
				die "cannot end METHOD here in $template_id starting at line $tag->{start_line}";
			}
			
			$cur_method = 'main';
		}
		
		# MERGE_PERL TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'MERGE_PERL') {
			
			if ($restricted) {
				die "invalid tag '$tag->{text}' in template '$template_id' starting at line $tag->{start_line}";
			}
			
			# FORMAT THE PERL
			my $source = "\t\$Result .= (";
			
			my @lines = split /\n/, $tag->{text};
			
			while ($_ = shift @lines) {
				$source .= $_;
				if (not @lines) {
					$source .= ");\n";
				}
			}
			
			$methods{$cur_method} .= $format_perl->($source, $tag->{start_line});
		}
		
		# CAPTURE_PERL TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'CAPTURE_PERL') {
			
			if ($restricted) {
				die "cannot use CAPTURE_PERL tag in restricted template '$template_id' starting at line $tag->{start_line}";
			}
			
			push @stack, 'CAPTURE_PERL';
			push @stack_details, $tag->{text};
			push @stack_lines, $tag->{start_line};
			
			$methods{$cur_method} .= "\tpush(\@ResultStack, ''); local \*Result = \\\$ResultStack[-1];\n";
		}
		
		# /CAPTURE_PERL TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq '/CAPTURE_PERL') {
			
			if (pop(@stack) ne 'CAPTURE_PERL') {
				die "unexpected /CAPTURE_PERL tag in $template_id starting at line $tag->{start_line}";
			}
			
			my $capture_lvalue = pop @stack_details;
			my $capture_line = pop @stack_lines;
			
			$methods{$cur_method} .= $format_perl->("\t$capture_lvalue = pop(\@ResultStack); local \*Result = \\\$ResultStack[-1];\n", $capture_line);
		}
		
		# FILTER_PERL TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'FILTER_PERL') {
			
			if ($restricted) {
				die "cannot use FILTER_PERL tag in restricted template '$template_id' starting at line $tag->{start_line}";
			}
			
			push @stack, 'FILTER_PERL';
			push @stack_details, $tag->{text};
			push @stack_lines, $tag->{start_line};
			
			$methods{$cur_method} .= "\tpush(\@ResultStack, ''); local \*Result = \\\$ResultStack[-1];\n";
		}
		
		# /FILTER_PERL TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq '/FILTER_PERL') {
			
			if (pop(@stack) ne 'FILTER_PERL') {
				die "unexpected /FILTER_PERL tag in $template_id starting at line $tag->{start_line}";
			}
			
			my $filter_code = pop @stack_details;
			my $filter_line = pop @stack_lines;
			
			$methods{$cur_method} .= $format_perl->("\t\$ResultStack[-2] .= ($filter_code); pop(\@ResultStack); local \*Result = \\\$ResultStack[-1];\n", $filter_line);
		}
		
		# REGEX TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'REGEX') {
			
			if ($restricted) {
				die "cannot use REGEX tag in restricted template '$template_id' starting at line $tag->{start_line}";
			}
			
			push @stack, 'REGEX';
			push @stack_details, $tag->{text};
			push @stack_lines, $tag->{start_line};
			
			$methods{$cur_method} .= "\tpush(\@ResultStack, ''); local \*Result = \\\$ResultStack[-1];\n";
		}
		
		# /REGEX TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq '/REGEX') {
			
			if (pop(@stack) ne 'REGEX') {
				die "unexpected /REGEX tag in $template_id starting at line $tag->{start_line}";
			}
			
			my $regex = pop @stack_details;
			my $regex_line = pop @stack_lines;
			
			$methods{$cur_method} .= $format_perl->("\t\$Result =~ $regex; \$ResultStack[-2] .= \$Result; pop(\@ResultStack); local \*Result = \\\$ResultStack[-1];\n", $regex_line);
		}
		
		# MERGE TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'MERGE') {
			
			# PARSE THE EXPRESSION
			my $parsed_expr = el_parse($tag->{text}, $template_id, $tag->{start_line});
			
			# COMPILE IT TO PERL
			$methods{$cur_method} .= $format_perl->("\t\$Result .= (" . el_compile($parsed_expr, $template_id, $tag->{start_line}) . ");\n", $tag->{start_line});
		}
		
		# EXEC TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'EXEC') {
			
			# PARSE THE EXPRESSION
			my $parsed_expr = el_parse($tag->{text}, $template_id, $tag->{start_line});
									
			# COMPILE IT TO PERL
			$methods{$cur_method} .= $format_perl->("\t" . el_compile($parsed_expr, $template_id, $tag->{start_line}) . ";\n", $tag->{start_line});
		}
		
		# SET TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'SET') {
			
			# PARSE THE EXPRESSION
			my $parsed_expr = el_parse($tag->{text}, $template_id, $tag->{start_line});
			
			# MAKE SURE WE GOT A SET EXPRESSION
			if ($parsed_expr->{type} ne 'opr' or $parsed_expr->{opr} ne '=') {
				die "expected '=' in SET tag in $template_id on line $tag->{start_line}";
			}
						
			# COMPILE IT TO PERL
			$methods{$cur_method} .= $format_perl->("\t" . el_compile($parsed_expr, $template_id, $tag->{start_line}) . ";\n", $tag->{start_line});
		}
		
		# RETURN TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'RETURN') {
			
			# PARSE THE EXPRESSION
			my $parsed_expr = el_parse($tag->{text}, $template_id, $tag->{start_line});
									
			# COMPILE IT TO PERL
			$methods{$cur_method} .= $format_perl->("\treturn " . el_compile($parsed_expr, $template_id, $tag->{start_line}) . ";\n", $tag->{start_line});
		}
		
		# IF TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'IF') {
			
			# PARSE THE EXPRESSION
			my $parsed_expr = el_parse($tag->{text}, $template_id, $tag->{start_line});
			
			# COMPILE TO PERL
			$methods{$cur_method} .= $format_perl->("\tif (" . el_compile($parsed_expr, $template_id, $tag->{start_line}) . ") {\n", $tag->{start_line});
			
			# PUSH IT ON THE STACK
			push @stack, 'IF';			
		}
		
		# ELSIF TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'ELSIF') {
			
			if ($stack[-1] ne 'IF') {
				die "unexpected ELSIF tag (no opening IF tag) in $template_id on line $tag->{start_line}";
			}
			
			# PARSE THE EXPRESSION
			my $parsed_expr = el_parse($tag->{text}, $template_id, $tag->{start_line});
			
			# COMPILE TO PERL
			$methods{$cur_method} .= $format_perl->("\t} elsif (" . el_compile($parsed_expr, $template_id, $tag->{start_line}) . ") {\n", $tag->{start_line});
		}
		
		# ELSE TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'ELSE') {
			
			if ($stack[-1] ne 'IF') {
				die "unexpected ELSE tag (no opening IF tag) in $template_id on line $tag->{start_line}";
			}
			
			$methods{$cur_method} .= $format_perl->("\t} else {\n", $tag->{start_line});
		}
		
		# WHILE TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'WHILE') {
			
			# PARSE THE EXPRESSION
			my $parsed_expr = el_parse($tag->{text}, $template_id, $tag->{start_line});
			
			# COMPILE TO PERL
			$methods{$cur_method} .= $format_perl->("\twhile (" . el_compile($parsed_expr, $template_id, $tag->{start_line}) . ") {\n", $tag->{start_line});
			
			# PUSH IT ON THE STACK
			push @stack, 'WHILE';			
		}
		
		# FOREACH TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'FOREACH') {
			
			# PARSE THE EXPRESSION
			my ($var_expr, $expr_src) = el_parse($tag->{text}, $template_id, $tag->{start_line});
			
			# MAKE SURE WE GOT A VAR EXPRESSION
			if ($var_expr->{type} ne 'variable') {
				die "expected variable in FOREACH tag in $template_id on line $tag->{start_line}";
			}
			
			# LOOK FOR THE 'in' PART
			if ($expr_src !~ s/^\s*in\b//) {
				die "expected 'in' in FOREACH tag in $template_id on line $tag->{start_line}";
			}
			
			# GRAB THE LIST EXPRESSION
			my $list_expr = el_parse($expr_src, $template_id, $tag->{start_line});
			
			# COMPILE TO PERL
			my $var_compiled = el_compile($var_expr, $template_id, $tag->{start_line});
			
			# THIS IS LAME, BUT IT WORKS
			$var_compiled =~ s/el_lookup\(/el_set\(\$_foreach_item, /;
			
			my $list_compiled = el_compile($list_expr, $template_id, $tag->{start_line});
			
			$methods{$cur_method} .= $format_perl->("\tforeach my \$_foreach_item (\@{el_foreach_array($list_compiled)}) {\n", $tag->{start_line});
			$methods{$cur_method} .= $format_perl->("\t\t$var_compiled;\n", $tag->{start_line});
			
			# PUSH IT ON THE STACK
			push @stack, 'FOREACH';			
		}
		
		# END TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'END') {
			
			if ($stack[-1] eq 'IF' or $stack[-1] eq 'WHILE' or $stack[-1] eq 'FOREACH') {
				$methods{$cur_method} .= $format_perl->("\t}\n", $tag->{start_line});
				pop @stack;
			}
			else {
				die "unexpected END tag in $template_id on line $tag->{start_line}";
			}
		}
		
		# CAPTURE TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'CAPTURE') {
						
			push @stack, 'CAPTURE';
			push @stack_details, $tag->{text};
			push @stack_lines, $tag->{start_line};
			
			$methods{$cur_method} .= "\tpush(\@ResultStack, ''); local \*Result = \\\$ResultStack[-1];\n";
		}
		
		# /CAPTURE TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq '/CAPTURE') {
			
			if (pop(@stack) ne 'CAPTURE') {
				die "unexpected /CAPTURE tag in $template_id starting at line $tag->{start_line}";
			}
			
			my $capture_lvalue = pop @stack_details;
			my $capture_line = pop @stack_lines;
			
			# PARSE THE EXPRESSION
			my $parsed_expr = el_parse("$capture_lvalue = \$Result", $template_id, $capture_line);
			
			# COMPILE THE EXPRESSION
			my $compiled_expr = el_compile($parsed_expr, $template_id, $capture_line);
			
			$methods{$cur_method} .= $format_perl->("\t$compiled_expr; pop(\@ResultStack); local \*Result = \\\$ResultStack[-1];\n", $capture_line);
		}
		
		# FILTER TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq 'FILTER') {
			
			push @stack, 'FILTER';
			push @stack_details, $tag->{text};
			push @stack_lines, $tag->{start_line};
			
			$methods{$cur_method} .= "\tpush(\@ResultStack, ''); local \*Result = \\\$ResultStack[-1];\n";
		}
		
		# /FILTER TAG
		# ---------------------------------
		
		elsif ($tag->{type} eq '/FILTER') {
			
			if (pop(@stack) ne 'FILTER') {
				die "unexpected /FILTER tag in $template_id starting at line $tag->{start_line}";
			}
			
			my $filter_code = pop @stack_details;
			my $filter_line = pop @stack_lines;
			
			# PARSE THE EXPRESSION
			my $parsed_expr = el_parse($filter_code, $template_id, $filter_line);
			
			# COMPILE THE EXPRESSION
			my $compiled_expr = el_compile($parsed_expr, $template_id, $filter_line);
			
			$methods{$cur_method} .= $format_perl->("\t\$ResultStack[-2] .= ($compiled_expr); pop(\@ResultStack); local \*Result = \\\$ResultStack[-1];\n", $filter_line);
		}
		
		# TAG_STYLE TAG (just ignore these
		# ---------------------------------
		
		elsif ($tag->{type} eq 'TAG_STYLE') {
		
			# THESE ARE PRE-PROCESSED, SO WE SHOULD COMPLETELY IGNORE THEM HERE
			
		}
		
		# UNRECOGNIZED TAG
		# ---------------------------------
		
		else {
		
			die "unrecognized tag type '$tag->{type}' in $template_id starting at line $tag->{start_line}";
			
		}
	}
	
	# MAKE SURE OUR MODE IS COOL
	if ($cur_method eq 'init') {
		die "expected /INIT tag in $template_id";
	}
	elsif ($cur_method ne 'main') {
		die "expected /METHOD tag in $template_id";
	}
	
	if (@stack) {
		die "expected /$stack[-1] tag in $template_id";
	}
		
	# NOW, WE CONSTRUCT THE ENTIRE PACKAGE
	# --------------------------------------
	
	# DUMPER THE TEMPLATE ID
	my $dumper = Data::Dumper->new([$template_id]);
	$dumper->Useqq(1);
	$dumper->Indent(0);
	$dumper->Terse(1);
	my $template_id_literal = $dumper->Dump();
	
	# WHICH METHODS ARE SUPPORTED IN THE EL
	my $tmojo_el_i_can = join(' ', qw(template_id tmojo), keys %methods);
	
	# PUT TOGETHER THE PACKAGE
	my $template_compiled = qq{###TMOJO_TEMPLATE_ID: $template_id
package $package_name;

use strict;

use LabZero::Fail;
use LabZero::Tmojo::ExpressionLanguage;

our \$Tmojo;
our \$TMOJO_TEMPLATE_ID = $template_id_literal;
our \@ISA;

$global_section

sub new {					
	my \$Self = {
		args    => \$_[1],
		next    => \$_[2],
		vars    => {},
		init    => {},
	};
	
	# PUT THE OTHER HASHES IN ARGS FOR THE EXPRESSION LANGUAGE
	\$Self->{vars}{Args} = \$Self->{args};
	\$Self->{vars}{Next} = \$Self->{next};
	\$Self->{vars}{Init} = \$Self->{init};
	
	bless \$Self, \$_[0];
	
	# CALL init IF IT EXISTS
	if (\$Self->can('init')) {
		\$Self->init;
	}
	
	# RETURN THE VALUE
	return \$Self;
}

sub template_id {
	return \$TMOJO_TEMPLATE_ID;
}

sub tmojo {
	return \$Tmojo;
}

sub tmojo_el_can {
	my \$self = \$_[0];
	my \$method_name = \$_[1];
	
	if (grep { \$_ eq \$method_name } qw($tmojo_el_i_can)) {
		return 1;
	}
	
	my \%seen;
	foreach my \$parent_class (\@ISA) {
		if (my \$code = \$parent_class->can("tmojo_el_can")) {
			if (not \$seen{\$code}) {
				if (\$self->\$code(\$method_name)) {
					return 1;
				}
				\$seen{\$code} = 1;
			}
		}
	}
	
	return undef;
}

	};
	
	foreach my $method (keys %methods) {
		my $start_line = $method_start_lines{$method};
		$template_compiled .= qq{
sub $method {
	my \$Self = shift \@_;

	my \@R = eval {
	
		# DEFINE THE IMPLICIT VARIABLES
		my \$Next  = \$Self->{next};
		my \$Args  = \$Self->{args};
		our \%Args; local \*Args = \$Self->{args};
		our \%Vars; local \*Vars = \$Self->{vars};
		our \%Init; local \*Init = \$Self->{init};
		
		# THESE THREE ARE A LITTLE SCEEERY
		local \$Self->{vars}{Self} = \$Self;
		local \$Self->{vars}{MethodArgs} = \\\@_;
		local \$Self->{vars}{Tmojo} = \$Tmojo;
		
		my \@ResultStack = ('');
		our \$Result; local \*Result = \\\$ResultStack[-1];
		
		# --- BEGIN USER CODE ---
$methods{$method}
		# --- END USER CODE ---
	
		return \$Result;
	};
#line $start_line TMOJO($template_id)
	fling(\$\@) if \$\@;
	
	if (wantarray) {
		return \@R;
	}
	else {
		return \$R[0];
	}
}
		};
	}
	
	$template_compiled .= "\n1;\n";
	
	# RETURN THE COMPILED TEMPLATE
	return $template_compiled;
}

sub get_template_class {

	my ($self, $template_id, $used_parents) = @_;
		
	# NORMALIZE THE TEMPLATE_ID
	my $normalized_template_id = $self->normalize_template_id($template_id);
	
	# GET THE PACKAGE NAME
	my $package_name = $self->{template_packages}{$normalized_template_id};
	if ($package_name eq '') {
		my $index = ++$LAST_TEMPLATE_PACKAGE_INDEX;
		$package_name = "LabZero::Tmojo::Templates::T$index";
		$self->{template_packages}{$normalized_template_id} = $package_name;
	}
	
	# IS THE TEMPLATE CACHED AT ALL?
	my $in_cache = 0;
	
	# CHECK THE MEMORY CACHE TO SEE IF WE HAVE THIS ALREADY
	my $cache_time_stamp = 0;
	if (exists $self->{last_compile_times}{$normalized_template_id}) {
		$cache_time_stamp = $self->{last_compile_times}{$normalized_template_id};
		$in_cache = 1;
	}
	
	# OK, NOW ASK THE TEMPLATE LOADER IF WE'RE ALL SET!
	my ($use_cached, $template_lines, $restricted, $time_to_use_as_compile_time) = $self->{template_loader}->load_template($normalized_template_id, $cache_time_stamp);
	
	# COMPILE THE TEMPLATE IF IT ISN'T CACHED
	if ($use_cached == 0 or $in_cache == 0) {
		# WE DON'T HAVE THIS CACHED AT ALL, COMPILE IT, LOAD IT (AND MAYBE SAVE A FILE)
		
		if ($self->{glog}) {
			my $glog = $self->{glog};
			my $event = $in_cache ? 'RECOMPILING': 'COMPILING';
			$glog->event($event, "$$ $package_name $normalized_template_id");
		}
		
		# COMPILE THE TEMPLATE
		my $template_compiled = eval {
			return compile_template($template_lines, $normalized_template_id, $package_name, $restricted);
		};
		fling ($@) if $@;
		
		# DELETE THE EXISTING PACKAGE AND LOAD
		delete_package($package_name);
				
		# PUT A CONTEXTUAL TMOJO OBJECT INTO THE PACKAGE
		{
			no strict 'refs';
			my $context_path = $normalized_template_id;
			$context_path =~ s{/[^/]+$}{};
			my $contextual_tmojo = LabZero::Tmojo->new(%$self, context_path => $context_path);
			${$package_name . '::Tmojo'} = $contextual_tmojo;
		}
		
		# EVAL THE COMPILED CODE USING OUR HIDDEN EVAL THINGY
		LabZero::Tmojo::HiddenEval::__eval_template($template_compiled, $package_name);
		
		# UPDATE THE MEMORY CACHE
		$self->{last_compile_times}{$normalized_template_id} = $time_to_use_as_compile_time || time();
	}
	
	# MAKE SURE THAT LOAD TEMPLATE HAS BEEN CALLED ON THE PARENT TEMPLATES
	{
		no strict 'refs';
		
		# MAKE SURE THAT WE DON'T HAVE AN INFINITE LOOP HERE
		if (defined $used_parents) {
			if ($used_parents->{$normalized_template_id} == 1) {
				fail("circular parent reference, $normalized_template_id already used (this will cause an infinite loop)");
			}
		}
		else {
			$used_parents = {};
		}
		
		$used_parents->{$normalized_template_id} = 1;
		
		my @parents = @{$package_name . '::TMOJO_ISA'};
		
		if (@parents) {
			foreach (@parents) {
				my $contextual_tmojo = ${$package_name . '::Tmojo'};
				$_ = $contextual_tmojo->get_template_class($_, $used_parents);
			}
			
			@{$package_name . '::ISA'} = @parents;
		}
	}
	
	# RETURN THE PACKAGE NAME
	return $package_name;
}

sub normalize_template_id {
	my ($self, $template_id) = @_;
	
	# DON'T DO PREFIX MAGIC IF WE HAVE A NAMESPACE
	if ($template_id !~ m/^(\w*):/) {
		# THIS IS WHERE THE MAGIC OF THE CONTEXT PATH IS RESOLVED
		if (substr($template_id, 0, 3) eq '../') {
			my $context_path = $self->{context_path};
		
			while (substr($template_id, 0, 3) eq '../') {
				$context_path =~ s{/[^/]*$}{};
				$template_id = substr($template_id, 3);
			}
		
			$template_id = "$context_path/$template_id";
		}
		elsif (substr($template_id, 0, 1) ne '/') {
			$template_id = "$self->{context_path}/$template_id";
		}
	}
	
	# HANDLE UPWARD TRAVERSAL
	if (substr($template_id, -1, 1) eq '^') {
		$template_id = substr($template_id, 0, -1);
		
		while (rindex($template_id, '/') > 0) {
			if ($self->{template_loader}->template_exists($template_id)) {
				last;
			}
			else {
				$template_id =~ s{/[^/]+/([^/]+)$}{/$1};
			}
		}
	}
	
	# NOW WE'VE GOT OUR NAME
	return $template_id;
}

package LabZero::Tmojo::HiddenEval;

sub __eval_template {
	eval($_[0]);
	LabZero::Fail::fling($@) if $@;
}

1;
