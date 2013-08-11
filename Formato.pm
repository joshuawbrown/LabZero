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
###########################################################################

package LabZero::Formato_Hash;

use strict;

=head1 LabZero::Formato

Formato is a a tied hash with versatile formatting
machinery for formatting numbers and stuff. The
power of it is that it is a tied hash, so it
interpolates within strings.

Formato can be controlled with some package
variables. It can do everything that sprintf
can do plus a few other nifty doodles.

=head1 Usage

Just include formato in your code, and then
when you want to format a number, just use
it like this:

print "$Formato{fdpc2_5}{$number}";

f-c are formatting modes, 2 and five are decimal placement and alignment.
The numbers are optional (default for both is zero)

%Formato is a package variable that gets exported.
The formatting options are controlled by the first key passed.

=head1 Options:

f <-- MEANS NOTHING, placeholder only

c <-- Use commas as 'thousands' seperators
P <-- Output a fraction as percentage
p <-- Parenthesis for negatives
d <-- Prefix with a dollar sign
z <-- Return '' instead of zero

t <-- Format the number as a timestamp, digits is a format choice

r <-- Justify right instead of left
Z <-- pad left with zeros

h <-- Input is decimal number, convert to FakeHex. 
H <-- Input is FakeHex, convert to FakeHex

a <-- Input is alphanumeric, not a number
w <-- wrap text to specified number of columns (as in $Formato{w40}...)
T <-- format text to title case

F <-- format string as a US phone number, implies 'a'

=over 5

h/H DO NOT SUPPORT PLACES OR PADDING. Padding may come later but is not implemented.

=back

first number <-- INTEGER Places after the decimal

second number  <-- INETEGER, TOTAL MINUMUM WIDTH, paded left with spaces

=cut


my %formatter_cache;

sub TIEHASH {
	my $self = shift;
	my $data = {};
	return bless $data, $self;
}

sub FETCH {

	my %params;
	my $config = $_[1];

	if ($config =~ /^z_([^_]+)_([FZPTfLcpdkKswtrahH]*)((\d+)(_(\d+))?)?$/) {
	
		$params{zero_replace} = $1;
		my $options = $3 . 'z';
		$params{places} = int($5);
		$params{spaces} = int($7);
		
		while ($options ne '') { $params{chop($options)} = 1;	}

		if (not exists($formatter_cache{$config})) {
			my %num_formatter;
			tie %num_formatter, 'LabZero::Formato_Hash_Sub', %params;
			$formatter_cache{$config} = \%num_formatter;
		}
		
		return $formatter_cache{$config};

	} elsif ($config =~ /^([FZTPfcpdzkKswtLrahH]+)((\d+)(_(\d+))?)?$/) {
	
		my $options = $1;
		$params{places} = int($3);
		$params{spaces} = int($5);
		
		while ($options ne '') { $params{chop($options)} = 1;	}

		if (not exists($formatter_cache{$config})) {
			my %num_formatter;
			tie %num_formatter, 'LabZero::Formato_Hash_Sub', %params;
			$formatter_cache{$config} = \%num_formatter;
		}
		
		return $formatter_cache{$config};
	
	} else {
		die "MODE ERROR\nillegal Formato formatting mode $_[1]\nModes: f (none) c (use commas) p (paren for -) d (dollar signs) z (blank for zero) z_foo_ (foo for zero) t (number is a 
time) a (alpha, not numeric) h (decimal to fakehex) H (fakehex to decimal)\n" . 'Usage: print "$Formato{fcpdz2_5}{$number}"' . "\n";
	}
	
}

##############################
# THE INTERMEDIATE TIED HASH #
##############################

package LabZero::Formato_Hash_Sub;

use POSIX qw(strftime);

our $time_offset;
our $time_zone;


##########################
# display seconds in     #
# human friendly format #
##########################

sub seconds_to_string {
	
	# USAGE: print seconds_to_string($elapsed);
	
	my $sec = $_[0];
	my $str = '';
	
	if ($sec >= 31449600)   { $str =sprintf('%1.1f yrs', $sec / 31449600); }
	elsif ($sec >= 604800)  { $str =sprintf('%1.1f wks', $sec / 604800); }
	elsif ($sec >= 86400)   { $str =sprintf('%1.1f days', $sec / 86400); }
	elsif ($sec >= 3600)    { $str =sprintf('%1.1f hrs', $sec / 3600); }
	elsif ($sec >= 60)      { $str =sprintf('%1.1f min', $sec / 60); }
	else                    { $str =sprintf('%1.1f sec', $sec); }

	return $str;
}


################################
# FAKEHEX / DECIMAL CONVERSION #
###############################

my $fake_hex = 'UEHJ234Y6789RKXW';
my $real_hex = '0123456789ABCDEF';

sub decimal_to_fakehex {
	my ($decimal) = @_;
	my $hex  = sprintf('%X', $decimal);
	eval "\$hex =~ tr/$real_hex/$fake_hex/, 1" or die $@;
	return($hex);
}

sub fakehex_to_decimal {
	my ($hex) = @_;
	$hex = uc($hex);
	eval "\$hex =~ tr/$fake_hex/$real_hex/, 1" or die $@;
	my $int  = sprintf('%d', hex("0x$hex") );               
	return($int);
}

sub phone_format {

	# phone string in, formatted phone string out
	
	my $ph = $_[0];
	$ph = reverse $ph;
	
	if ($ph =~ /^(\d\d\d\d)(\d\d\d)(\d\d[23456789])$/) { $ph = "$1-$2 )$3("; }
	elsif ($ph =~ /(\d\d\d\d)(\d\d\d)(\d*)/) { $ph = "$1-$2-$3"; }
	
	$ph = reverse $ph;
	
	for ($ph) {
		$ph =~ s/^(\-|\s)+//;
		$ph =~ s/(\-|\s)+$//;
	}
	
	return "$ph";
        
}

# convert text to title case

sub title_case {
	
	my ($word) = @_;
	if (length($word) eq '2') { return lc($word); }
	if (uc($word) eq 'I') { return uc($word); }
	if (uc($word) =~ m/^(AND|THE)$/) { return lc($word); }
	else { return ucfirst(lc($word)); }
	
}

# wrap text to n columns

sub wrap_text {

	my ($text, $length, $indent) = @_;
	
	# FIRST, SPLIT INTO LINES
	my @source_lines = split /\n/, $text;
	my @result_lines;
	
	# WRAP THE LINES
	SOURCELINE: foreach my $source_line (@source_lines) {
	
		if ($source_line =~ /^\s*$/) {
			push @result_lines, '';
			next SOURCELINE;
		}
		
		while (length($source_line) > $length) {
		my $split_point = $length;
		while (substr($source_line, $split_point, 1) !~ /\s/) {
			$split_point -= 1;
			
			if ($split_point < 0) {
				push @result_lines, $source_line;
				next SOURCELINE;
			}
		}
		
		push @result_lines, substr($source_line, 0, $split_point);
			$source_line = substr($source_line, $split_point + 1);
		}
		
		if (length($source_line) > 0) {
			push @result_lines, $source_line;
		}
	}
	
	# DONE, DUDE
	my $cr_indent = "\n" . (' ' x $indent);
	return (' ' x $indent) . join $cr_indent, @result_lines;
}


# Formato_Hash_Sub:
# A hash that formats numbers

sub TIEHASH {
	my ($self, %params) = @_;
	my $data = { %params };
	return bless $data, $self;
}

#######################
# THE GUTS OF FORMATO #
#######################

sub FETCH {

	my ($params, $number) = @_;
	
	my $output;
	
	# HANDLE DATES FIRST
	
	if ($params->{t}) {
	
		my $mode = $params->{places};
		
		my $time_name;
		
		if ($params->{L}) {
			$time_name = " $time_zone"; 
			$number += (60*60*$time_offset);
		}
		
		if (($number == 0) and ($mode<6)) { $number = time(); }
		
		if ($mode == 0)     { $output = strftime ("%H:%M:%S", localtime($number)) . $time_name; }
		elsif ($mode == 1)  { $output = strftime ("%l:%M %p",  localtime($number)) . $time_name; }
		elsif ($mode == 2)  { $output = strftime ("%Y%b%d %H:%M",  localtime($number)) . $time_name; }
		elsif ($mode == 21) { $output = strftime ("%Y-%m-%d %T",  localtime($number)) . $time_name; }
		elsif ($mode == 3)  { $output = strftime ("%d-%b-%Y %l:%M %p",  localtime($number)) . $time_name; }
		elsif ($mode == 4)  { $output = strftime ("%b %e, %Y",  localtime($number)); }
		elsif ($mode == 5)  { $output = strftime ("%b %e, %Y at %l:%M %p",  localtime($number)) . $time_name; }
		elsif ($mode == 6)  { $output = seconds_to_string($number); }
		elsif ($mode == 7)  { $output = strftime ("%d.%m.%Y um %H:%M Uhr",  localtime($number)) . $time_name; } # GERMAN LONG
		else { $output = "MODE $mode"; }
		
		if ($params->{s}) { $output =~ s/  / /g; }
		
	} elsif ($params->{h}) {

		$output = decimal_to_fakehex($number);
	
	} elsif ($params->{H}) {

		$output = fakehex_to_decimal($number);
	
	} elsif ($params->{F}) {
	
		$output = $number;
		$output =~ s/(\d{7,})/phone_format($1)/eg;
	
	} elsif ($params->{a}) {
	
		$output = $number;
	
	# HANDLE NUMBERS
	
	} else {
	
		my $places = $params->{places};
	
		# Divide by computer terms for k and M suffixes
		
		my $suffix;
		if ($params->{k}) {
			if ($number > 1000000) {
				$suffix = 'M';
				$number = $number / 1000000;
				if ($places == 0) { $places = 1; }
			} elsif ($number > 1000) {
				$suffix = 'k';
				$number = $number / 1000;
				if ($places == 0) { $places = 1; }		
			}
		}

		if ($params->{K}) {
			if ($number > 1048576) {
				$suffix = 'M';
				$number = $number / 1048576;
				if ($places == 0) { $places = 1; }
			} elsif ($number > 1024) {
				$suffix = 'k';
				$number = $number / 1024;
				if ($places == 0) { $places = 1; }		
			}
		}

		# Handle percentage
		if ($params->{P})  {
			$number = 100 * $number;
		}
	
		# Abstract the negative bit
		
		my $negatory = 0;
		if ($number < 0) { $negatory = 1; }
		$number = abs($number);
		
		# Seperate fraction and integer
		
		my $integer = int($number);
		my $fraction = $number - int($number);
		
		# Format decimal fraction
		
		if ($places > 0) {
			for (1..$places) { $fraction = $fraction * 10; }
			$fraction = sprintf("\%0.0f", $fraction);
			if (length($fraction) > $places) { 
				$fraction = 0; $integer += 1;
			}
			while (length($fraction) < $places) { $fraction = '0' . $fraction; }
		} else {
			$fraction = '';
			$number = sprintf("\%0.0f",$number);
		}
		
		# Add commas to integer
		if ($params->{c}) { while ($integer =~ s/(\d)(\d\d\d)\b/$1,$2/) {} }
		
		$output = "$integer.$fraction";
		if (substr($output,-1,1) eq '.') { chop $output; }
		
		# Return a blank instead of zero, if requested
		
		if ($params->{z}) {
			if (($fraction == 0) and ($integer == 0)) {
				$output = $params->{zero_replace};
				$negatory = 0;
			}
		} elsif (($fraction == 0) and ($integer == 0)) {
			$negatory = 0;
		}
	
		# Conditionally add suffix
		if (($suffix ne '') and ($output ne ''))  {
			$output .= $suffix;
		}
	
		# Conditionally add dollar
		if (($params->{d}) and ($output ne ''))  {
			$output = '$' . $output;
		}

		# Handle percentage
		if (($params->{P}) and ($output ne ''))  {
			$output = $output . '%';
		}
		
		# left zero padding
		if ($params->{Z} and ($params->{spaces} > 0)) {
			my $spaces = $params->{spaces};
			if ($negatory and $params->{p}) { $spaces -= 2; }
			elsif ($negatory) { $spaces -= 1; }
			$output =  ('0' x ($spaces - length($output))) . $output;
		}
		
		# Negatory, dude
		if ($negatory) {
			if ($params->{p}) { $output = "($output)"; }
			else { $output =  '-' . $output; }
		} elsif ($params->{p}) {
			$output =  ' ' . $output . ' ';
		}
	
	}
	
	if ($params->{T}) {
		$output =~ s{\b(\w+)\b}{title_case($1)}eg;
		$output = ucfirst($output);
	}
	
	# text wrapping
	
	if ($params->{w}) {
		$output = wrap_text($output, $params->{places}, $params->{spaces});
	}
	
	# Alignment padding

	elsif ($params->{spaces} > length($output)) {
		
		if ($params->{r}) {
			$output =  $output . (' ' x ($params->{spaces} - length($output)));
		} else {
			$output = (' ' x ($params->{spaces} - length($output))) . $output;
		}
		
	}

	return $output;
	
}


######################
# THE ACTUAL PACKAGE #
######################

package LabZero::Formato;

use strict;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw(%Formato formato_set_timezone);

# The hash itself

our %Formato;
tie %Formato, 'LabZero::Formato_Hash';

my %timezone_lookup = (
	2  => 'EST',
	1  => 'CST',
	0  => 'MST',
	-1 => 'PST',
	-2 => 'ALS',
	3  => 'ATL',
	-3 => 'HWI',
	7  => 'LON',
	17 => 'AUS',
);

sub formato_set_timezone {

	my ($offset) = @_;
	
	$LabZero::Formato_Hash_Sub::time_offset = $offset;
	$LabZero::Formato_Hash_Sub::time_zone = $timezone_lookup{$time_offset};
	
}

return 1;
