#!/usr/bin/perl

### LPC SIMPLIFIED MSGLITE WORKER DAEMON ###

# This daemon listens to msglite for incoming web requests sent by NginX. It evals
# a handler library to handle each request, then returns the results to msglite,
# which replies to nginx. It's an alternative to fastCGI. Technically a daemon
# coudl be written in any language, and you can run as many daemons as you find
# practical.

use strict;

use JSON;
use Data::Dumper;
use POSIX qw(strftime);
use Time::HiRes;

# use Devel::Leak;

use LabZero::Fail;
use LabZero::MsgLite;
use LabZero::RetroHTML;

$| = 1;

############
## USAGE ###
############

# http_worker.pl worker_id=XXX dev_mode=1 handler=Foo::Bar max_requests=XXX

#### PARSE SETTINGS ###

my $usage = "Usage: http_worker.pl <commands>
Valid Commands:
  handler=Foo::Bar (Perl Lib Path) * REQUIRED
  msglite_socket=UNIX SOCKET PATH * REQUIRED
  
  msglite_inbox=X (Default: lpc.http_worker)
  worker_id=X (0-255, default 1)
  dev_mode=X (1 or 0, default 0)
  max_requests=X (1 to MAXINT, default 10000)
  silent=1
  
";

my %commands;
foreach my $arg (@ARGV) {
	if ($arg =~ m/^([a-zA-Z_]+)=(.+)/) { $commands{$1} = $2; }
}

unless ($commands{max_requests})  { $commands{max_requests} = 10000; }
unless ($commands{worker_id})     { $commands{worker_id} = 1; }
unless ($commands{msglite_inbox}) { $commands{msglite_inbox} = 'lpc.http_worker'; }

unless ($commands{handler}) {
	fail("You must specify a handler!", $usage);
}

unless ($commands{msglite_socket}) {
	fail("You must specify a msglite_socket!", $usage);
}

my $start_log = join(' ', map { $_ . '=' . $commands{$_} } (keys %commands));

### Try to load devs config
my %dev_ips;
if ($ENV{LABZERO_CONFIG} =~ m{^(.+)/context\.config$}) {
	my $path = $1 . '/devs.txt';
	if (-f $path) {
		if (open(my $fh, $path)) {
			while(<$fh>) {
				if (m/(\d+\.\d+\.\d+\.\d+)/) {
					$dev_ips{$1} = 1;
				}
			}
			close($fh);
		}
	}
}

#### Connect to MSGLite
my $msglite = LabZero::MsgLite->at_unix_socket($commands{msglite_socket});

#### GO!

my $handler_failed;
my $handler_loaded;

my $last_mark = time();

# This whole thing is in a closure! how cool is that?

{

	# Safe signal handling
	my $quit = 0;
	$SIG{HUP}  = sub { logger("SIGNAL HUP ($$)"); $quit = 1; };
	$SIG{INT}  = sub { logger("SIGNAL INT ($$)"); $quit = 1; };
	$SIG{QUIT} = sub { logger("SIGNAL QUIT ($$)"); $quit = 1; };
	$SIG{TERM} = sub { logger("SIGNAL TERM ($$)"); $quit = 1; };
	
	# Quit after a random number of requests
	my $request_counter = 0;
	my $request_limit = int($commands{max_requests}/2) + int(rand($commands{max_requests}/2));
	
	logger("STARTED ($$) - $start_log");
	my $term_message;
		
	while (not $quit) {

		# IN DEV MODE, IF WERE SITTING IDLE, OUTPUT TO THE LOGFILE TO KEEP TAIL ALIVE
		if ($commands{dev_mode} and (time() - $last_mark) >= 86400) {
			$last_mark = time();
			logger('STILL ALIVE');
		}

#   Devel::Leak memory debugging code
#		my $handle; # apparently this doesn't need to be anything at all
#		my $leaveCount = 0;
#		my $enterCount = Devel::Leak::NoteSV($handle);
		
		# WAIT FOR THE NEXT AVAILABLE MSG FROM MSGLITE
		my $msglite_message = $msglite->ready(1, $commands{msglite_inbox});
		next if !defined($msglite_message);
		
		# IF QUIT BECAME TRUE WHILE WE WERE WAITING, RE-QUEUE THE MESSAGE AND QUIT
		if ($quit) {
			$msglite->send($msglite_message);
			$term_message = " - Worker expired, message re-queued";
			last;
		}
		
		# IN DEV MODE, RESTART IF WE ALREADY HANDLED A REQUEST
		# AND IF THIS DEV USER MATCHES THE DEV USER IP!
		my ($remote_ip) = $msglite_message->{body} =~ m/"X-Real-Ip":"([\.0-9]+)"/;
		my $is_dev = $dev_ips{$remote_ip};
		
		if ($is_dev and ($request_counter > 0)) {
			$msglite->send($msglite_message);
			$term_message = " - Restarting for dev (IP $remote_ip)";
			last;
		}
		
		# REQUIRE THE HANDLER PACKAGE IN TIS OWN EVAL BUT INSIDE THE LOOP, SO THAT THE
		# DAEMON DIES AND LOGS THE ERROR BUT DOESN'T MAKE UPSTART GIVE UP ON IT IF IT'S
		# HOPELESSLY BUSTED!
				
		my $start_request = Time::HiRes::time();
		
		if (not $handler_loaded) { # only try this once
		
			if ($commands{handler} !~ m/\w+::\w+/) {
				fail("Failed to specify a valid perl module!\n$usage", "Specified handler: $commands{handler}");
			}
			
			else {
				# Manually convert to a package name, then eval it.
				my $package_path = $commands{handler};
				$package_path =~ s{::}{/}g;
				$package_path .= '.pm';
				eval { require $package_path };
				if ($@) {
					# If our handler failed, make a note of it
					warn($@);
					$handler_failed = 1;
				}
				else {
					# If it worked, mark it as done so we dont do it again
				 $handler_loaded = 1;
				}
			}
		
		}
		
		### CALL THE HANDLER IN an EVAL FOR FRIENDLIER ERRORS

		#### Parse this message, handle the request
		my $request_string = '-';
		my $handler_request;
		
		my $error_handler = sub {
			my $stamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
			return "[$stamp] Error $_[0]: $_[1] \"$_[2]\"\n";
		};
		
		my ($status_code, $headers, $body) = eval {

			# Decode the JSON of the message body here for nice logging.
			my $browser_request = decode_json($msglite_message->body);
			$request_string = "$browser_request->{method} $browser_request->{url}";
			
			# Hack for returning very brief errors to non-browsers like curl
			my $agent = $browser_request->{headers}{'User-Agent'};
			$browser_request->{auth_developer} = $is_dev;

			# if the handler failed to load (earlier), just bail out here
			if ($handler_failed) {
				return ('500', ['Content-Type' => 'text/html'], $error_handler->(500, 'Main Handler failed compliation (W101)', $commands{handler}));
			}
			
			# Create and invoke the handler, and pass in the decoded json, as well as the original msglite request
			my $return_body;
			$handler_request = LabZero::RequestObject->new($browser_request, $msglite_message);
			my ($return_status, $return_headers, $plz_quit) = $handler_request->execute_handler($commands{handler}, \$return_body);
			if ($plz_quit) { logger("TERMINATE REQUESTED BY HANDLER ($$)"); $quit = 1; }

			# Return the results
			return ($return_status, $return_headers, $return_body);
			
		};
		
		# Handle errors and log any STDERR stuff
		
		my ($reply, $encoded_reply, $notation);
		
		# Handle deferred replies
		if ($status_code == 999) {
			logger("999 $request_string DEFERRED");
			# Note, when deferred, we don't get the body!
		}
		else {
		
			# Internal error
			if ($@) {
				$notation = " - Handler '$commands{handler}' failed at runtime\n$@";
				$status_code = '500';
				$headers = ['Content-Type' => 'text/html'];
				$body = $error_handler->(500, 'Runtime Error (W102)', $request_string);
			}
			
			# Failed to generated HTTP status code
			elsif (not $status_code) {
				$notation = " - No HTTP status code from Handler '$commands{handler}'";
				$status_code = '500';
				$headers = ['Content-Type' => 'text/html'];
				$body = $error_handler->(500, 'No HTTP Status code returned! (W103)', $request_string);
			}
			
			# Failed to generate a header
			elsif ((ref($headers) ne 'ARRAY') or (not scalar(@$headers))) {
				l$notation = " - No valid HTTP header from Handler '$commands{handler}'";
				$status_code = '500';
				$headers = ['Content-Type' => 'text/html'];
				$body = $error_handler->(500, 'No valid HTTP header returned! (W104)', $request_string);
			}
			
			my $elapsed_request = sprintf("%0.2f", Time::HiRes::time() - $start_request);
			$elapsed_request .= 's';
			
			### Send the output back to nginx
			$reply = ["$status_code", $headers];
			$encoded_reply = encode_json($reply);
			
			# Success - Dev mode logging
			if ($commands{dev_mode} or $notation) {
				logger("$status_code $request_string $encoded_reply$notation ($elapsed_request)");
			}
			
			# Success - Standard logging
			elsif (not $commands{silent}) { 
				logger("$status_code $request_string ($elapsed_request)");
			}
			
			# Send a msglite reply
			$msglite->send($encoded_reply, 10, $msglite_message->reply_addr);
			if ($body ne '') { $msglite->send($body, 10, $msglite_message->reply_addr); }
			$msglite->send('', 10, $msglite_message->reply_addr);
			
			#Just in case, get the http_body msg so it doesn't clog up the queue
			$handler_request->get_http_body;
		
		}
				
		$handler_request = undef;
		
#   Devel::Leak memory debugging code
#		$leaveCount = Devel::Leak::CheckSV($handle);
#		logger("MMMM $enterCount - $leaveCount");
		
		# Increment the request counter
		$request_counter += 1;
		if ($request_counter >= $request_limit) {
			logger("limit reached ($$): $request_counter requests");
			$quit = 1;
		}
		
	} # while (not $quit)
	
	logger("TERMINATED ($$) $term_message");
	
}

sub logger {

	my $stamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
	
	{
		local $| =1;
		print "[$stamp]$commands{worker_id}> $_[0]\n";
	}
}

package LabZero::RequestObject;

use strict;

use Data::Dumper;
use POSIX qw(strftime);

use LabZero::Fail;


### my $request = LabZero::RequestObject;
### Creates a new request object with the info in it

sub new {
	
	my ($class, $browser_request, $msglite_msg) = @_;
		
	my $self = {
		browser_request => $browser_request,
		msglite_msg     => $msglite_msg,
		plz_quit        => 0,
		http_body_retrieved => 0,
		headers => [],
	};
	bless $self, $class;
	return $self;

}

### $request->execute_handler($package_name)
### Calls a handler library with itself as a parameter

sub execute_handler {

	my ($self, $package_name, $body_reference) = @_;
	
	### TAKES SELF AND PACKAGE NAME and REF TO THE BODY CONTENT
	### RETURNS BACK $return_status, $return_headers
	
	LABZERO_HTTP_HANDLER: {
		$package_name->handle_request($self);
	}
	
	continue {
		fail("No http result code was returned.\nYou must TERMINATE by calling http_ok, http_redirect, http_err or http_send_file");
	}
	
	# If we got here, we either finished or we last out of it
	# examine the headers and look for a content type
	
	my $have_content_type = 0;
	foreach my $key (@{ $self->{headers} }) {
		if (lc($key) eq 'content-type') { $have_content_type = 1; last; }
		if (lc($key) eq 'x-accel-redirect') { $have_content_type = 1; last; }
	}
	
	if (not $have_content_type) {
		push @{ $self->{headers} }, 'Content-Type', 'text/html; charset=UTF-8';
	}
		
	# Decide what to do with the body content
	
	if (ref($self->{content}) eq 'SCALAR') { $body_reference = $self->{content}; }
	elsif (ref($self->{content}) eq '')    { $$body_reference = $self->{content}; }
	else { $$body_reference = ''; }
	
	# Return the status code and headers
	return ($self->{result_code}, $self->{headers}, $self->{plz_quit});

}

### my $post = $request->retrieve_post()
### Get the post from msglite, and return it
### or return the cached version

sub get_http_body {
	
	my ($self) = @_;
	
	if (not $self->{http_body_retrieved}) {
		my $post_msg = $msglite->ready(10, $self->{browser_request}{bodyAddr});
		$self->{http_body} = $post_msg->{body};
		$self->{http_body_retrieved} = 1;
	}
	
	return $self->{http_body};

}

### my $post = $request->retrieve_post()
### Get the post from msglite, and return it
### or return the cached version

sub ajax {
	
	my ($self) = @_;
	
	if ($self->{browser_request}{headers}{'X-Requested-With'} eq 'XMLHttpRequest') { return 1; }
	return undef;

}


### $request->http_ok($content)
### End the request and return OK to the apache server

sub http_ok {
	
	my ($self, $content) = @_;
	if ($content) { $self->http_content($content); }
	$self->{result_code} = 200;
	last LABZERO_HTTP_HANDLER;

}

### $request->http_error($error_code)
### Return the specified error code, or 500 if not specified

sub http_err {
	
	my ($self, $error_code, $content) = @_;
	if ($content) { $self->http_content($content); }
	unless ($error_code) { $error_code = 500; }
	$self->{result_code} = $error_code;
	last LABZERO_HTTP_HANDLER;

}

### $request->http_fatal_err($error_code, $content)
### Return the specified error code, or 500 if not specified
### SETS A FLAG TO THE HANDLER TO DIE BECAUSE THE ERROR COULD HAVE SCREWED UP THE INTERNAL STATE
### USEFUL FOR DEALING WITH COMPILE ERRORS IN ON_DEMAND LOADING!

sub http_fatal_err {
	
	my ($self, $error_code, $content) = @_;
	if ($content) { $self->http_content($content); }
	unless ($error_code) { $error_code = 500; }
	$self->{result_code} = $error_code;
	$self->{plz_quit} = 1;
	last LABZERO_HTTP_HANDLER;

}

### $request->http_result($error_code)
### End the request and return an arbitrary numeric result code

sub http_result {

	my ($self, $result_code) = @_;
	unless ($result_code) { die "http_result requires a numeric result code"; }
	$self->{result_code} = $result_code;
	last LABZERO_HTTP_HANDLER;

}

### $request->http_redirect($url)
### End the request and return a redirect URL

sub http_redirect {

	my ($self, $location) = @_;
	$self->{body} = undef;
	$self->http_header('Location' => $location);
	if ($location eq '') { fail("http_redirect requires a non empty location"); }
	$self->{result_code} = '302';
	last LABZERO_HTTP_HANDLER;

}

### $request->http_content($content)
### Sets the body content to be sent to the browser
### Takes a scalar or a scalar reference

sub http_content {

	my ($self, $content) = @_;

	if (ref($content) eq 'SCALAR') { $self->{content} = $content; }
	elsif (ref($content) eq '')    { $self->{content} = $content; }
	else { fail("Content must be a scalar or scalar ref"); }
	
}

### $request->http_header("Set-Cookie" => $some_cookie ....)
### Set an http header

sub http_header {

	my ($self, @pairs) = @_;
	
	while (@pairs) {
		my $key = shift @pairs;
		my $value = shift @pairs;
		
		if ($key eq '') { fail("http_header requires a non empty key", \@pairs); }
		if ($value eq '') { fail("http_header requires a non empty value for the key '$key'", \@pairs); }
		
		push @{ $self->{headers} }, $key, $value;
	}	
	
}

### $request->http_content_type('text/html')
### Set an http_content_type header

sub http_content_type {

	my ($self, $content_type) = @_;
	$self->http_header('Content-type' => $content_type);

}

### $request->http_send_file($path)
### Send a file using slurp mode. Oh yeah.

sub http_send_file {

	my ($self, $path) = @_;
	
	open my $fh, $path;
	local $/ = undef;
	my $bytes = <$fh>;
	close $fh;
	
	$self->{static} = 1;
	$self->{content} = \$bytes;
	$self->http_ok;
	
}

### $request->http_send_file_accel($path)
### Send a file using slurp mode. Oh yeah.

sub http_send_file_accel {

	my ($self, $path, $filename) = @_;
	
	$self->http_header('X-Accel-Redirect' => $path);
	
	if ($filename) {
		$self->http_header('Content-Type' => 'application/octet-stream');
		$self->http_header('Content-Disposition' => "attachment; filename=\"$filename\"");
	}
	
	$self->{content} = "X-Accel-Redirect $path\n";
	$self->{result_code} = '100';
	$self->{static} = 1;
	last LABZERO_HTTP_HANDLER;
	
}

### $request->http_defer($content)
### Defer the request and don't reply to msglite
### This allows the handler to deal with it later

sub http_defer {
	
	my ($self) = @_;
	$self->{result_code} = 999;
	last LABZERO_HTTP_HANDLER;

}

1;