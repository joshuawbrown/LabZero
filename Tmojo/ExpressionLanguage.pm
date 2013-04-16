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

package LabZero::Tmojo::ExpressionLanguage;

use strict;

use Data::Dumper;
use LabZero::Fail;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(el_parse el_compile el_lookup el_set el_empty el_exists el_foreach_array el_flatten el_method_call);

our %opr_precedence = (
	'+'       => 50,
	'-'       => 50,
	'*'       => 60,
	'/'       => 60,
	
	'=='      => 30,
	'!='      => 30,
	'eq'      => 30,
	'ne'      => 30,
	'>'       => 30,
	'<'       => 30,
	'>='      => 30,
	'<='      => 30,
	
	'empty'   => 100,
	'not'     => 100,
	'exists'  => 100,
	'flatten' => 100,
	
	'and'     => 10,
	'or'      => 10,
	
	'~'       => 40,
	
	'='       => 5,
	
	'.'       => 110,
	
	'['       => 110,
	
	','       => 1,
	'=>'      => 1,
	
	';'       => 2,
);

sub el_parse {
	my ($source, $template_id, $line_number) = @_;
	
	my $skip_ws = sub {
		$source =~ m/\G\s+/gc;
	};
		
	my $parse_error = sub {
		fail("$_[0] in $template_id on line $line_number");
	};
	
	my $parse_expression;
	$parse_expression = sub {
		my ($precedence) = @_;
		
		# SKIP WHITE SPACE
		$skip_ws->();
		
		my $result;
		
		if ($source =~ m/\G(empty|not|exists|flatten|\*)/gc) {
			# UNARY OPR
			my $opr = $1;
			
			if ($opr eq '*') {
				$opr = 'flatten';
			}
			
			$result = { type => 'opr', opr => $opr, term => $parse_expression->($opr_precedence{$opr}) };
		}
		elsif ($source =~ m/\G(-?\d+(\.\d+)?)/gc) {
			# NUMERIC LITERAL
			$result = { type => 'number', value => $1 };
		}
		elsif ($source =~ m/\G([a-zA-Z_]\w*)\(/gc) {
			# BUILT-IN FUNCTION
			$result = { type => 'function', function_name => $1 };
			
			if ($source =~ m/\G\s*\)/gc) {
				$result->{arguments} = [];
			}
			else {
				$result->{arguments} = [ _unroll_expression_list($parse_expression->(0), ',') ];
							
				$skip_ws->();
				
				if ($source !~ m/\G\)/gc) {
					$parse_error->("expected ')'");
				}
			}
		}
		elsif ($source =~ m/\G([a-zA-Z_]\w*\b)(?!\()/gc) {
			# BAREWORD!!! WE'LL MAKE SURE THIS IS OK
			my $value = $1;
			
			if ($source !~ m/\G(?=\s*(=>|\]))/gc) {
				$parse_error->("illegal bareword '$value'");
			}
			
			$result = { type => 'string', value => $value, bareword => 1 };
		}
		elsif ($source =~ m/\G'/gc) {
			# AH, A SIMPLE STRING LITERAL... LET'S PARSE IT!
			
			if ($source !~ m/\G((?:[^'\\]++|\\[\\'])*+)'/gc) {
				$parse_error->("invalid string literal");
			}
			
			my $value = $1;
			$value =~ s/\\(.)/$1/g;
			
			$result = { type => 'string', value => $value };
		}
		elsif ($source =~ m/\G"/gc) {
			# DOUBLE-QUOTES AREN'T ACTUALLY LEGAL
			$parse_error->("double-quoted strings aren't supported. Use single quotes");
		}
		elsif ($source =~ m/\G\$/gc) {
			# A VARIABLE!
			$result = { type => 'variable', exprs => [] };
			
			if ($source =~ m/\G([a-zA-Z0-9_]+)/gc) {
				$result->{exprs}[0] = { type => 'string', value => $1 };
			}
			
			while ($source =~ m/\G\[/gc) {
				push @{$result->{exprs}}, $parse_expression->(0);
				
				$skip_ws->();
				
				unless ($source =~ m/\G\]/gc) {
					$parse_error->("expected ']'");
				}
			}
		}
		elsif ($source =~ m/\G\@/gc) {
			# AN ARGUMENT
			$result = { type => 'argument', exprs => [] };
			
			if ($source =~ m/\G([a-zA-Z0-9_]+)/gc) {
				$result->{exprs}[0] = { type => 'string', value => $1 };
			}
			
			while ($source =~ m/\G\[/gc) {
				push @{$result->{exprs}}, $parse_expression->(0);
				
				$skip_ws->();
				
				unless ($source =~ m/\G\]/gc) {
					$parse_error->("expected ']'");
				}
			}
		}
		elsif ($source =~ m/\G\(/gc) {
			# SUB EXPRESSION
			$result = $parse_expression->(0);
			
			unless ($source =~ m/\G\)/gc) {
				$parse_error->("expected ')'");
			}
		}
		else {
			$parse_error->("invalid expression start: " . substr($source, pos($source), 20));
		}
		
		# NOW LOOK FOR BINARY OPERATORS
		for (;;) {
			$skip_ws->();
			
			if ($source =~ m/\G(\+|-|\*|\/|==|!=|eq\b|ne\b|>=|<=|>|<|and\b|or\b|~|=>|=|\.|\[|,|;)/gc) {
				my $opr = $1;
				my $new_prec = $opr_precedence{$opr};
				
				if ($new_prec > $precedence) {
					if ($opr eq '[') {
						# LOOKUP SYNTAX
						$result = { type => 'lookup', target => $result, exprs => [] };
						
						do {
							push @{$result->{exprs}}, $parse_expression->(0);
							
							$skip_ws->();
							
							unless ($source =~ m/\G\]/gc) {
								$parse_error->("expected ']'");
							}
						} while ($source =~ m/\G\[/gc);
					}
					elsif ($opr eq '.') {
						# METHOD CALL
						if ($source !~ m/\G([a-zA-Z_]\w*)/gc) {
							$parse_error->("expected method name");
						}
						
						my $method_name = $1;
						my $args_expr_list = [];
						
						# LOOK FOR AN ARGUMENT LIST
						if ($source =~ m/\G\(/gc) {
							unless ($source =~ m/\G\s*\)/gc) {
								$args_expr_list = [ _unroll_expression_list($parse_expression->(0), ',') ];
								
								$skip_ws->();
								
								if ($source !~ m/\G\)/gc) {
									$parse_error->("expected ')'");
								}
							}
						}
						
						$result = { type => 'method_call', method_name => $method_name, target => $result, arguments => $args_expr_list };
					}
					elsif ($opr eq ',' and $source =~ m/\G(?=\s*\))/gc) {
						# THIS IS A TRAILING COMMA, JUST SKIP IT
						pos($source) = pos($source);
					}
					elsif ($opr eq ';' and $source =~ m/\G(?=\s*$)/gc) {
						# THIS IS A TRAILING SEMI-COLON, JUST SKIP IT
						pos($source) = pos($source);
					}
					else {
						# BINRAY OPERATOR
						$opr = ',' if $opr eq '=>';
						$result = { type => 'opr', opr => $opr, left => $result, right => $parse_expression->($new_prec) };
					}
				}
				else {
					# THE NEXT OPERATOR'S PRECEDENCE IS LOWER THAN THE CURRENT PRECEDENCE
					pos($source) = pos($source) - length($opr);
					last;
				}
			}
			else {
				# WE DON'T SEE ANY BINARY OPERATORS UP AHEAD IN $source
				last;
			}
		}
		
		# RETURN THE RESULT
		return $result;
	};
	
	# PARSE IT
	my $expr = $parse_expression->(0);
	
	# AND NOW WE FINISH UP
	$skip_ws->();
	
	if (wantarray) {
		return ($expr, substr($source, pos($source)));
	}
	else {
		if ($source !~ m/\G$/gc) {
			$parse_error->("expected end of expression: '" . substr($source, pos($source), 20) . "'");
		}
	
		return $expr;
	}
}

sub el_compile {
	my ($expression, $template_id, $line_number) = @_;
	
	my $compile_error = sub {
		fail("$_[0] in $template_id on line $line_number");
	};
	
	my $do_compile;
	$do_compile = sub {
		my ($expression) = @_;
		
		if ($expression->{type} eq 'number') {
			return "$expression->{value}";
		}
		elsif ($expression->{type} eq 'string') {
			local $Data::Dumper::Terse = 1;
			local $Data::Dumper::Indent = 0;
			return Dumper($expression->{value});
		}
		elsif ($expression->{type} eq 'variable') {
			# THERE ARE SOME SUPER MAGICAL VARIABLES
			if (scalar(@{$expression->{exprs}}) == 1 and $expression->{exprs}[0]{value} eq 'Result') {
				return "\$Result";
			}
			else {			
				my @lookups;
				foreach my $expr (@{$expression->{exprs}}) {
					push @lookups, $do_compile->($expr);
				}
				
				return "el_lookup(\\\%Vars, " . join(', ', @lookups) . ")";
			}
		}
		elsif ($expression->{type} eq 'argument') {
			# HANDLE DIRECT AGRUMENTS
			my @lookups;
			foreach my $expr (@{$expression->{exprs}}) {
				push @lookups, $do_compile->($expr);
			}
			
			return "el_lookup(\\\%Args, " . join(', ', @lookups) . ")";
		}
		elsif ($expression->{type} eq 'opr') {
			my $opr = $expression->{opr};
			
			if ($opr eq 'not') {
				return "(not " . $do_compile->($expression->{term}) . ")";
			}
			elsif ($opr eq 'empty') {
				return "el_empty(" . $do_compile->($expression->{term}) . ")";
			}
			elsif ($opr eq 'exists') {
				# MAKE SURE THE TERM IS A VARIABLE
				if ($expression->{term}{type} ne 'variable') {
					$compile_error->("expected variable as argument to exists");
				}
				
				my @lookups;
				foreach my $expr (@{$expression->{term}{exprs}}) {
					push @lookups, $do_compile->($expr);
				}
				
				return "el_exists(\\\%Vars, " . join(', ', @lookups) . ")";
			}
			elsif ($opr eq 'flatten') {
				return "el_flatten(" . $do_compile->($expression->{term}) . ")";
			}
			elsif ($opr eq '=') {
				# MAKE SURE THE LEFT IS A VARIABLE
				if ($expression->{left}{type} ne 'variable') {
					$compile_error->("expected variable for '='");
				}
				
				# MAKE SURE THEY AREN'T SETTING A MAGIC VARIABLE
				if (scalar(@{$expression->{left}{exprs}}) == 1 and $expression->{left}{exprs}[0]{value} eq 'Result') {
					$compile_error->("cannot set \$Result");
				}
				
				my @lookups;
				foreach my $expr (@{$expression->{left}{exprs}}) {
					push @lookups, $do_compile->($expr);
				}
				
				return "el_set(" . $do_compile->($expression->{right}) . ", \\\%Vars, " . join(', ', @lookups) . ")";
			}
			elsif ($opr eq ';') {
				my $result = "sub {" . join('; ', map { $do_compile->($_) } _unroll_expression_list($expression, ';')) . "}->()";
			}
			elsif ($opr eq ',') {
				$compile_error->("unexpected ','");
			}
			else {
				my $result = '(' . $do_compile->($expression->{left});
				if ($opr eq '~') {
					$opr = '.';
				}
				
				$result .= " $opr " . $do_compile->($expression->{right}) . ')';
				
				return $result;
			}
		}
		elsif ($expression->{type} eq 'method_call') {		
			my $result = "el_method_call(scalar(" . $do_compile->($expression->{target}) . "), '" . $expression->{method_name} . "'";
			foreach my $arg_expr (@{$expression->{arguments}}) {
				$result .= ", " . $do_compile->($arg_expr);
			}
			$result .= ")";
			
			return $result;
		}
		elsif ($expression->{type} eq 'lookup') {
			my @lookups;
			foreach my $expr (@{$expression->{exprs}}) {
				push @lookups, $do_compile->($expr);
			}
			
			return "el_lookup(scalar(" . $do_compile->($expression->{target}) . "), " . join(', ', @lookups) . ")";
		}
		elsif ($expression->{type} eq 'function') {
			if ($expression->{function_name} eq 'array') {
				return "[" . join(', ', map { $do_compile->($_) } @{ $expression->{arguments} }) . "]";
			}
			elsif ($expression->{function_name} eq 'hash') {
				return "{" . join(', ', map { $do_compile->($_) } @{ $expression->{arguments} }) . "}";
			}
			elsif ($expression->{function_name} eq 'if') {
				return "(" . $do_compile->($expression->{arguments}[0]) . " ? " .
					$do_compile->($expression->{arguments}[1]) . " : " .
					$do_compile->($expression->{arguments}[2]) . ")";
			}
			elsif ($expression->{function_name} =~ /^(substr|sprintf|uc|ucfirst|lc|length|index|time|rand)$/) {
				return $expression->{function_name} . '(' . join(', ', map { $do_compile->($_) } @{ $expression->{arguments} }) . ')';
			}
			elsif ($expression->{function_name} eq 'hash_keys') {
				return '[keys %{' . $do_compile->($expression->{arguments}[0]) . '}]';
			}
			elsif ($expression->{function_name} eq 'array_length') {
				return 'scalar(@{' . $do_compile->($expression->{arguments}[0]) . '})';
			}
			elsif ($expression->{function_name} eq 'join') {
				return 'join(' . $do_compile->($expression->{arguments}[0]) . ', @{' . $do_compile->($expression->{arguments}[1]) . '})';
			}
			elsif ($expression->{function_name} =~ /^(push|pop|shift|unshift)$/) {
				my @args_copy = @{ $expression->{arguments} };
				shift @args_copy;
				return $expression->{function_name} . '(@{' . $do_compile->($expression->{arguments}[0]) . '}, ' . join(', ', map { $do_compile->($_) } @args_copy) . ')';
			}
			else {
				$compile_error->("unknown function $expression->{function_name}");
			}
		}
	};
	
	return $do_compile->($expression);
}

sub _unroll_expression_list {
	my ($args_expr, $opr) = @_;
	
	my @args_expr_list;
	
	while ($args_expr->{type} eq 'opr' and $args_expr->{opr} eq $opr) {
		unshift @args_expr_list, $args_expr->{right};
		$args_expr = $args_expr->{left};
	}
	
	unshift @args_expr_list, $args_expr;
	
	return @args_expr_list;
}

sub el_lookup {
	my $current = shift @_;
	
	while (@_) {
		if (ref($current) eq 'HASH') {
			$current = $current->{shift(@_)};
		}
		elsif (ref($current) eq 'ARRAY') {
			$current = $current->[shift(@_)];
		}
		else {
			return undef;
		}
	}
	
	return $current;
}

sub el_set {
	my $value = shift @_;
	my $current = shift @_;
	
	while (@_ > 1) {
		if (ref($current) eq 'HASH') {
			$current = $current->{shift(@_)};
		}
		elsif (ref($current) eq 'ARRAY') {
			$current = $current->[shift(@_)];
		}
		else {
			die "can't find item " . shift(@_);
		}
	}
	
	if (ref($current) eq 'HASH') {
		$current->{shift(@_)} = $value;
	}
	elsif (ref($current) eq 'ARRAY') {
		$current->[shift(@_)] = $value;
	}
	else {
		die "not a container";
	}	
}

sub el_empty {
	my ($perl_val) = @_;
	
	if ((not defined($perl_val)) or $perl_val eq '') {
		return 1;
	}
	else {
		return '';
	}
}

sub el_exists {
	my $current = shift @_;
	
	while (@_) {
		my $next_key = shift @_;
		if (ref($current) eq 'HASH') {
			if (exists($current->{$next_key})) {
				$current = $current->{$next_key};
			}
			else {
				return '';
			}
		}
		elsif (ref($current) eq 'ARRAY') {
			if (exists($current->[$next_key])) {
				$current = $current->[$next_key];
			}
			else {
				return '';
			}
		}
		else {
			return '';
		}
	}
	
	return 1;
}

sub el_foreach_array {
	my ($val) = @_;
	
	if (ref($val) eq 'HASH') {
		return [ keys %$val ];
	}
	elsif (ref($val) eq 'ARRAY') {
		return $val;
	}
	else {
		return [ $val ];
	}
}

sub el_flatten {
	my ($val) = @_;
	
	if (ref($val) eq 'HASH') {
		return ( %$val );
	}
	elsif (ref($val) eq 'ARRAY') {
		return ( @$val );
	}
	else {
		return ( $val );
	}
}

sub el_method_call {
	my ($target, $method_name, @params) = @_;
	
	my $target_ref = ref($target);
	
	if (index($target_ref, '::') == -1) {
		freak("target doesn't look like an object (ref: $target_ref)", $target);
	}
	
	if (not $target->can('tmojo_el_can')) {
		freak("target object of type $target_ref doesn't support tmojo_el_can");
	}
	
	if (not $target->tmojo_el_can($method_name)) {
		my $target_name = ($target->can('tmojo_el_target_name') && $target->tmojo_el_target_name) || "target object of type $target_ref";
		freak("$target_name doesn't support method $method_name");
	}
	
	return $target->$method_name(@params);
}

1;