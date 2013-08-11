###########################################################################
# Copyright 2012 Joshua Brown
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

# This awesome lib replaces the old-school 'url utils" as well as the old "http arg parser"

package LabZero::HttpUtils;

use strict;

use POSIX qw(strftime);

use Time::HiRes;
use LWP::UserAgent;
use HTTP::Request;

use LabZero::Fail;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
	http_encode
	http_decode
	http_make_query
	http_parse_query
	http_cookie
	http_parse_cookies
	ip_int_to_quad
	ip_quad_to_int
	http_get
	http_post
	escape_js
);

=head2 http_encode

encodes a urlencoded string, replacing ' ' with ' '
and non-ok characters with%XX with the provided hex value 

=cut

sub escape_js {
	my ($value) = @_;
	$value =~ s{(?<!\\)'}{\\'}g;
	$value =~ s{<\/script>}{<' + '/script>}g;
	return "'" . $value . "'";
}

=head2 http_encode

encodes a urlencoded string, replacing ' ' with ' '
and non-ok characters with%XX with the provided hex value 

=cut

sub http_encode {
	my $string = shift;
	$string =~ s/([^-a-zA-Z0-9_ ])/sprintf "%%%02X", ord($1)/ge;
	$string =~ tr/ /+/;
	return $string;
}

=head2 http_decode

decodes a urlencoded string, replacing '+' with ' '
and %XX with the provided hex value we don;t bother to export this
stupid function, BTW

=cut

sub http_decode {
	
	my ($string, $charset) = @_;
	
	for ($string) {
		$string =~ tr/+/ /;
		$string =~ s/%([\da-f][\da-f])/chr(hex($1))/egi;
	}
	
	if ($charset ne '') {
		return decode($charset, $string);
	}
	else {
		return $string;
	}
}

=head2 http_make_query

example: http_make_query(%args);

=cut

sub http_make_query {

	my %args = @_;
	
	my @parts;
	foreach my $key (sort keys %args) {
		if (ref($args{$key}) eq 'ARRAY') {
			foreach my $value (@{ $args{$key} }) {
				push @parts, http_encode($key) . '=' .  http_encode($value);
			}
		}
		else {
			push @parts, http_encode($key) . '=' .  http_encode($args{$key});
		}
	}
	
	my $query = join ('&', @parts);

	return $query;

}

sub http_parse_query {
	my ($input, $charset) = @_;
	
	my %result;
	
	foreach my $pair (split /&/, $input) {
		my ($name, $value) = map { http_decode($_, $charset) } split(/=/, $pair);
		$result{$name} = $value;
	}
	
	return \%result;
}


=head2 ip_quad_to_int

example: ip_quad_to_int('10.0.0.1');

=cut

sub ip_quad_to_int {

	my ($quad) = @_;
	
	my ($a, $b, $c, $d) = split(/\./, $quad);
	my $ip_number = 0 + (16777216 * $a + 65536 * $b + 256 * $c + $d);

	return $ip_number;

}

=head2 ip_int_to_quad

example: ip_quad_to_int('10.0.0.1');

=cut

sub ip_int_to_quad {

	my ($int) = @_;
	
	my $hex_ip = sprintf('%08x', $int);
	my $quad = join('.', map { hex(substr($hex_ip, $_, 2)) } (0, 2, 4, 6));
	return $quad;

}

=head2 http_cookie

example: http_cookie(name => 'mycookie', value => 'myvalue', secure => 1);

=cut

sub http_cookie {

	my (%params) = @_;
	
	my $name    = $params{name} || freak("missing required parameter: name");
	if (not defined($params{value})) { freak("missing required parameter: value"); }
	my $value = $params{value};
	my $expires = $params{expires};
	my $domain  = $params{domain};
	my $path    = $params{path} || '/';
	my $secure  = $params{secure};
	
	my $cookie = "$name=$value";
	
	if ($expires > 0) {
		$cookie .= "; expires=" . strftime("%a, %d-%b-%Y %T GMT", gmtime($expires));
	}
	
	if ($domain ne '') {
		$cookie .= "; domain=$domain";
	}
	
	if ($path ne '') {
		$cookie .= "; path=$path";
	}
	
	if ($secure) {
		$cookie .= "; secure";
	}
	
	return $cookie;

}

=head2 http_parse_cookies

example: my %cookies = http_parse_cookies($headers{Cookie});

=cut

sub http_parse_cookies {

	my ($cookie_header) = @_;
	
	my %cookie_hash;
	my @cookies = split /;\s*/, $cookie_header;
	
	foreach my $cookie (@cookies) {
		my ($name, $value) = split /=/, $cookie, 2;
		$cookie_hash{$name} = $value;
	}
	
	return %cookie_hash;

}



#################
### HTTP GET ###
#################

=head2 http_get

example: my $result = http_get("SOME URL");
example: my ($code, $elapsed, $content) = http_get("SOME URL");

=cut

sub http_get {

	my ($url) = @_;
	
	my $ua = LWP::UserAgent->new('TESTER');
	my $elapsed;
	
	my $response = eval {
		local $SIG{ALRM} = sub { die("HTTP Post Error\nURL: $url\ERR: Timed Out after 60 seconds\n") };
		alarm 60;
		my $start = Time::HiRes::time();
		my $server_reply = $ua->get($url);
		$elapsed = Time::HiRes::time() - $start;
		alarm 0;
		return $server_reply;
	};
	
	if ($@) { return ("Failure during http get: $@\nURL $url", '600', $elapsed); }
	
	return ($response->code, $elapsed, $response->content); # For happy fun, content is the LAST item
	
}

#################
### HTTP POST ###
#################

=head2 http_post

example: my $result = http_post("SOME URL", \%post_data);
example: my ($code, $elapsed, $content) = http_get("SOME URL");

=cut

sub http_post {

	my ($url, $data) = @_;
	
	my $ua = LWP::UserAgent->new('TESTER');
	my $data_debug = join("\n", map { "$_=$data->{$_}" } %$data );
	my $elapsed;
	
	# push @{ $ua->requests_redirectable }, 'POST';

	my $response = eval {
		local $SIG{ALRM} = sub { die("HTTP Post Error\nURL: $url\ERR: Timed Out after 60 seconds\nData:\n$data_debug") };
		alarm 60;
		my $start = Time::HiRes::time();
		my $server_reply = $ua->post($url, $data);
		$elapsed = Time::HiRes::time() - $start;
		alarm 0;
		return $server_reply;
	};
	
	if ($@) { return("Failure during http post: $@\n URL: $url\nDATA: $data_debug", 600, $elapsed); }
	
	return ($response->code, $elapsed, $response->content); # For happy fun, content is the LAST item
	
}

