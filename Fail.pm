###########################################################################
# Copyright 2005 Lab-01 LLC
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

package LabZero::Fail;

=head1 LabZero::Fail

This module provides vastly improved functions for error reporting.


fail("message")

This function essentially replaces die. Error messages will contain
well formed call stacks.


freak("message")

This function works like croak from the Carp module. Same output
as fail, but the broken file is marked with a '*'


fret("message")

Replaces warn.


fuss("message")

Replaces carp.


All of these methods can be called with extra parameters which will
be displayed as clues. Strings are simply rendered, but references
are Dumpered... which is awesome.


fling($@) if $@;

Use fling to re-die (instead of just calling die). This will upgrade
runtime and compile errors with more information before propagating
them.

For example:

eval $runtime_code;
fling($@) if $@;


flog("message")

Prints the given message with the package name and line number. For succinct logging.


=cut


use strict;
use base qw(Exporter);

our @EXPORT = qw(fail freak fret fuss fling flog f_whoami);
our $DEBUG = 1;

sub fail {
	die LabZero::Error::Impl->new(1, 0, 0, @_);
}

sub freak {
	die LabZero::Error::Impl->new(1, 1, 0, @_);
}

sub fret {
	warn LabZero::Error::Impl->new(0, 0, 0, @_);
}

sub fuss {
	warn LabZero::Error::Impl->new(0, 1, 0, @_);
}

sub fling {
	die LabZero::Error::Impl->new(1, 0, 1, @_);
}

sub flog {

	my (undef, undef, $line) = caller(0);
	my (undef, undef, undef, $func) = caller(1);
	my ($package, $func_name) = $func =~ m/^(.+)\:\:(.+?)$/;
	print ">$package> $func_name (line $line): ", $_[0], "\n";
}

sub f_whoami {

	my (undef, undef, $line) = caller(0);
	my (undef, undef, undef, $func) = caller(1);
	my ($package, $func_name) = $func =~ m/^(.+)\:\:(.+?)$/;
	return "$package/$func_name/$line";
}

package LabZero::Error::Impl;

use overload '""' => \&stringify;

use Data::Dumper;

sub new {
	my ($class, $failure, $condescend, $propagated, $message, @clues) = @_;
	
	if (ref($message) eq 'LabZero::Error::Impl') {
		return $message;
	}
	
	my $self = {
		failure       => $failure,
		condescend    => $condescend,
		propagated    => $propagated,
		message       => $message,
		clues         => \@clues,
		broken_frame  => 0,
		debug         => $LabZero::Fail::DEBUG,
	};
	
	# CAPTURE THE STACK TRACE
	my @stack_trace;
	my $frame = 1;
	my $index = 0;
	my $start_filename;
	while (my @stack_info = caller($frame++)) {	
		my $stack_frame = {};
		my @keys = qw(package filename line subroutine hasargs wantarray evaltext is_require hints bitmask);
		for my $i (0..(@stack_info-1)) {
			$stack_frame->{$keys[$i]} = $stack_info[$i];
		}
		
		# SKIP eval {} FRAMES... THEY DON'T HELP THE USER
		if ($stack_frame->{subroutine} eq '(eval)' and $stack_frame->{evaltext} eq '') {
			next;
		}
		
		push @stack_trace, $stack_frame;
		
		if ($index == 0) {
			$start_filename = $stack_frame->{filename};
		}
		
		if ($condescend and $stack_frame->{filename} ne $start_filename and $self->{broken_frame} == 0) {
			$self->{broken_frame} = $index;
		}
		
		$index += 1;
	}
	
	$self->{stack_trace} = \@stack_trace;
	
	return bless $self, $class;
}

sub message {
	return $_[0]->{message};
}

sub all_stack_frames {
	return $_[0]->{stack_frames};
}

sub broken_stack_frame {
	my $self = shift;
	
	return $self->{stack_frames}[ $self->{broken_frame} ];
}

sub clues {
	return $_[0]->{clues};
}

sub stringify {
	my ($self) = @_;
	
	my $result = $self->{failure} ? 'FAILURE ' : 'WARNING ';
	
	if ($self->{message} eq '') {
		$result .= $self->{failure} ? 'Died' : 'Something\'s Wrong';
	}
	else {
		$result .= $self->{message};
	}
	
	if ($self->{debug}) {
		if ($self->{propagated}) {
			$result .= "PROPAGATED";
		}
	
		my $index = 0;
		foreach my $stack_frame (@{ $self->{stack_trace} }) {
			my $filename = $stack_frame->{filename};
			my $line = $stack_frame->{line};
			
			next if (($line == 0) and ($filename eq '/dev/null'));
			
			my $line_length = length("$line");
			my $pad = ' ' x (4 - $line_length);
			
			my $line_char = '|';
			if (!$self->{propagated} and $index == $self->{broken_frame}) {
				$line_char = '*';
			}
			
			$result .= "\n";
			$result .= "  $line_char line $pad$line of $filename";
			
			$index += 1;
		}
		
		if (@{ $self->{clues} }) {
			$result .= "\nCLUES\n";
			foreach my $clue (@{ $self->{clues} }) {
				
				$result .= "  > ";
				
				if (ref($clue) ne '') {
					local $Data::Dumper::Terse = 1;
					$result .= Dumper($clue);
				}
				else {
					$result .= "$clue\n";
				}
			}
		}
	}
	elsif ($self->{propagated}) {
		my $filename = $self->{stack_trace}[ $self->{broken_frame} ]{filename};
		my $line = $self->{stack_trace}[ $self->{broken_frame} ]{line};
		$result .= "PROPAGATED at $filename line $line.";
	}
	else {
		my $filename = $self->{stack_trace}[ $self->{broken_frame} ]{filename};
		my $line = $self->{stack_trace}[ $self->{broken_frame} ]{line};
		$result .= " at $filename line $line.";
	}
	
	return "$result\n";
}

1;
