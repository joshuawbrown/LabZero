###########################################################################
# Copyright 2013 Joshua Brown
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

package LabZero::Auth;

use strict;
use base qw(Exporter);

use Data::Dumper;

use LabZero::Fail;
use LabZero::HttpUtils;

my $days_30 = 60*60*24*30;

####################
#### CONSTRUCTOR ###
####################

=head2 CONSTRUCTOR - new(
	couch         => $couch,
	db_name       => 'some_name',
	expired_url   => '/expired.html',
	
	
	
	require_https => 1,
	timeout       => 60*60*72,
)

Creates a new AUTH object that stores the following stuff:
 
USAGE: new($couch_obj, 'database_name', '/expired.html')

=cut

sub new:method {

	my ($class, %params) = @_;

	unless ($params{couch})       { fail("Couch object required (couch)"); }
	unless ($params{db_name})     { fail("required: db_name"); }
	unless ($params{expired_url}) { fail("required: expired_url"); }
	unless ($params{timeout})     { $params{timeout} = 60*60*72; }
	
	flog(\%params);
	
	return bless \%params, $class;
	
	
	
}

# Make a host specific cookie name for auth and return it

sub _get_cookie_name {

	my ($self, $request) = @_;
	
	my $hostname = $request->{browser_request}{headers}{'X-Real-Host'} || $request->{browser_request}{headers}{'Host'};
	$self->{cookie_name} = 'labzero.' . $self->{db_name} . '.' . $hostname . '.auth';
		
	return $self->{cookie_name};

}

###########################
#### auth_verify_token ####
###########################

# USAGE: my $token = auth_verify_user($request);

# Verify that the session has a cookie OR Give a cookie and redirect to the /app/Login
# YOU DO NOT NEED TO CALL THIS IF YOU CALL auth_verify_user, but it won't hurt if u do

sub auth_verify_token {

	my ($self, $request) = @_;
	unless ($request) { fail("auth_verify_token requires the request object"); }
	
	my $http_req = $request->{browser_request};
	
	# Verify hostname if needed
	if ($self->{require_domain}) {
		my $hostname = lc($http_req->{headers}{'X-Real-Host'} || $request->{headers}{'Host'});
		# if required domain doesn't match, redirect to the required domain
		unless (lc($hostname) eq lc($self->{require_domain})) {
			my $redirect_url;
			if ($self->{require_https} or $http_req->{headers}{'X-Https'}) {
				$redirect_url = 'https://' . $self->{require_domain};
			} else {
				$redirect_url = 'http://' . $self->{require_domain};
			}
			$request->http_redirect($redirect_url);
		}
	}

	# Check for https and redirect if HTTPS is required
	if ($self->{require_https}) {
		if ($http_req->{headers}{'X-Https'} != 1) {
			my $hostname = lc($http_req->{headers}{'X-Real-Host'} || $request->{headers}{'Host'});
			my $secure_url = 'https://' . $hostname;
			if ($http_req->{query_string}) {
				$secure_url .=  '?' . $http_req->{query_string};
			}
			flog("* C - Redirecting from $hostname to $secure_url");
			$request->http_redirect($secure_url);
		}	
	}
	
	# Cookie Request
	my $cookie_name = $self->{cookie_name} || $self->_get_cookie_name($request);

	my $cookie_header = $http_req->{headers}{Cookie};
	my %cookies = http_parse_cookies($cookie_header);
	
	my $auth_token = $cookies{$cookie_name};

	# if we found a cookie, return the token
	if ($auth_token) {
		$http_req->{auth_token} = $auth_token;
		return $auth_token;
	}

	# If no cookie, give a cookie and kick back to the login page

	my $ip = $http_req->{headers}{'X-Real-Ip'};
	my $browser = $http_req->{headers}{'User-Agent'};
	my $hostname = $http_req->{headers}{'X-Real-Host'};
	my $timestamp = localtime();

	my $token = $self->{couch}->new_doc($self->{db_name}, {
		type => 'session',
		't' => $timestamp,
		'i' => $ip,
		'b' => $browser,
	});
	
	my $cookie;
	my $protocol;
	
	if ($self->{require_https}) {
		$cookie = http_cookie(
			name => $cookie_name,
			value => $token,
			domain => $hostname,
			secure => 1,
			expires => time() + $days_30
		);
		$protocol = 'https://';
	}
	else {
		$cookie = http_cookie(
			name => $cookie_name,
			value => $token,
			domain => $hostname,
			expires => time() + $days_30
		);
		$protocol = 'http://';
	}
		
	my $current_url = $protocol . 
		$http_req->{headers}{'X-Real-Host'} .
		$http_req->{url};
	
	if ($http_req->{query_string}) {
		$current_url .= '?' . $http_req->{query_string};
	}
	
	$request->http_header('Set-Cookie' => $cookie);
	$request->http_redirect($current_url);

}


#########################
### auth_verify_user ###
#########################

# USAGE: my $user = auth_verify_user($request);

# Verify that the session is logged in OR Send user the session expired notice

sub auth_verify_user {
	
	my ($self, $request, $allow_fail) = @_;
	unless ($request) { fail("auth_verify_token requires the request object"); }
	
	# If this user has already been verified in this session, just return the user
	if($request->{browser_request}{auth_user}) {
		return $request->{browser_request}{auth_user};
	}
	
	# Ensure that this session has a token
	my $token = $self->auth_verify_token($request);
	
	# Look up the token and see if it is validly logged in
	my $session_rec = $self->{couch}->get_doc($self->{db_name} => $token, 1);
	
	# if there is no record for the token, we need to delete that bad cookie to get out of a broken state!
	if (not $session_rec) {
		flog("> missing token record $token");
		my $html = redir_html($self->{expired_url});
		my $hostname = $request->{browser_request}{headers}{'X-Real-Host'};
		my $cookie_name = $self->{cookie_name} || $self->_get_cookie_name($request);
		my $cookie = http_cookie(name => $cookie_name, value => '', domain => $hostname);
		$request->http_header('Set-Cookie' => $cookie);
		$request->http_ok($html);
	}

	unless ($session_rec->{type} eq 'session') {
		fail("Internal Error: CouchDB record '$token' is not a session", Dumper($session_rec));
	}

	if (($session_rec->{status} eq 'auth') and ($session_rec->{expires} > time())) {
				
		# If authenticated, extend the session
		$self->{couch}->update_doc($self->{db_name} => $token, sub { $_[0]->{expires} = time() + $self->{timeout}; });
		
		# A handy app-wide hack so any handler can just look at the request to see if authed
		my %perm = map { $_ => 1 } (@{ $session_rec->{permissions} }); # Hash for quick lookup
		$request->{browser_request}{auth_user} = $session_rec->{user};
		$request->{browser_request}{auth_real_name} = $session_rec->{real_name};
		$request->{browser_request}{permissions} = \%perm;
						
		# And, return the username to the caller
		return $session_rec->{user}; # <-- TERMINAL
	}
	
	# If we go here then auth failed, so return the "your session is expired" page
	
	$self->{couch}->update_doc($self->{db_name} => $token, sub {
		if ($_[0]->{status} eq 'auth') {
			$_[0]->{status} = 'expired';
		}
	});
	
	# If $allow_fail is true, just nicely return undef
	if ($allow_fail) {
		return undef;
	}
	
	my $html = redir_html($self->{expired_url});
	$request->http_ok($html);

}

##########################
### auth_start_session ###
##########################

# Start a session that marks this session's cookie as
# authenticated to the given user's account

# usage: request, username, real name, [permissions]
# example:

# $auth->auth_start_session($request, 'SYSADMIN', 'SysAdmin', 'isAdmin', 'other_perm');

sub auth_start_session {

	my ($self, $request, $user_name, $real_name, @permissions) = @_;
	unless ($request) { fail("auth_verify_token requires the request object"); }
	if (not $user_name) { fail('auth_start_session requires a valid username'); }
	
	if (not scalar(@permissions)) { @permissions = (); }

	# Look for a browser cookie
	my $token = $self->auth_verify_token($request); # terminal function wont return if no session!

	# Make sure the token record exists in couch
	my $session_rec = $self->{couch}->get_doc($self->{db_name} => $token, 1);

	# if there is no record for the token, we need to delete that cookie to get out of a broken state!
	if (not $session_rec) {
		flog("> missing token record $token");
		my $html = redir_html($self->{expired_url});
		my $hostname = $request->{browser_request}{headers}{'X-Real-Host'};
		my $cookie_name = $self->{cookie_name} || $self->_get_cookie_name($request);
		my $cookie = http_cookie(name => $cookie_name, value => '', domain => $hostname);
		$request->http_header('Set-Cookie' => $cookie);
		$request->http_ok($html);
	}
	
	unless ($session_rec->{type} eq 'session') {
		fail('Couchdb record is not a session', Dumper($session_rec));
	}
	
	# So turn it into an authenticated session record!
	$self->{couch}->update_doc($self->{db_name} => $token, sub {
		$_[0]->{expires}     = time() + $self->{timeout};
		$_[0]->{user}        = $user_name;
		$_[0]->{real_name}   = $real_name;
		$_[0]->{status}      = 'auth';
		$_[0]->{permissions} = \@permissions;
	});
	
	flog("> Started session for $user_name (" . join(',', @permissions) . ')');
	return $token;
	
}

########################
### auth_end_session ###
########################

sub auth_end_session {

	my ($self, $request) = @_;
	unless ($request) { fail("auth_verify_token requires the request object"); }
	
	# Check for a token
	my $cookie_header = $request->{browser_request}{headers}{Cookie};
	my %cookies = http_parse_cookies($cookie_header);
	my $cookie_name = $self->{cookie_name} || $self->_get_cookie_name($request);
	my $token = $cookies{$cookie_name};
	if (not $token) { return; } # no token, we're done here
	
	# Look up the couch record in the DB
	my $session_rec = $self->{couch}->get_doc($self->{db_name} => $token);
	unless ($session_rec->{type} eq 'session') {
		fail('Couchdb record is not a session', Dumper($session_rec));
	}

	$self->{couch}->update_doc($self->{db_name} => $token, sub { $_[0]->{status} = 'terminated'; });
	flog("ended session for $session_rec->{user}");

}

sub redir_html {

	return qq(<!DOCTYPE HTML>
<html lang="en-US">
<head><meta charset="UTF-8">
<meta http-equiv="refresh" content="1;url=$_[0]">
<script type="text/javascript">window.location.href = "$_[0]"</script>
<title>Redirect</title></head>
<body>If you are not redirected automatically <a href='$_[0]'>Click Here</a></body>
</html>);

}


1; # This is a lib