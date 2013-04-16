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

package LabZero::Couch;

use strict;

use Time::HiRes;
use LWP::UserAgent;
use HTTP::Request;
use JSON;

use LabZero::Fail;
use Time::HiRes;
use POSIX;
use Data::Dumper;

my $base62 = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
my $epoch = 5333333333;

####################
#### CONSTRUCTOR ###
####################

=head2 CONSTRUCTOR - new($couch_url)

Creates a new COUCH object that stores the following stuff:

* Its couch URI
* Goodies for generating unique IDs
 
USAGE: new($couch_url)
OPTIONAL: new($couch_url, machine_id => 2, user => 'foo', password => 'bar')

=cut

sub new:method {

	my ($class, $couch_url, %params) = @_;
	
	unless ($couch_url) { fail("Valid couchdb URL required"); }
	
	my %self = (
		
		couch_url => $couch_url,
		machine_id => base62_encode(0),
		process_id => base62_encode($$,3),
		timer_id   => '',
		lwp_agent  => undef,
	);
	
	if ($params{machine_id} > 61) { fail("Invalid machine ID $params{machine_id} (Range 0-61)"); }
	if ($params{machine_id}) { $self{machine_id} = base62_encode($params{machine_id}, 1); }
	
	# connect to the server

	return bless \%self, $class;	
}

############
### INFO ###
############

sub info:method {

	my ($self, $db_name) = @_;

	my $info = $self->couch_request(GET => $db_name);
	
	my $perl_doc = decode_json($info);
	return $perl_doc;

}

###############
### GET DOC ###
###############

sub get_doc:method {

	my ($self, $db, $id) = @_;

	unless($db =~ m/^([_a-zA-Z0-9]+)$/) { fail("get_doc requires a DB name", "db=$db"); }
	unless($id =~ m/^([_a-zA-Z0-9]+)$/) { fail("get_doc requires a doc ID", "id=$id"); }

	my $doc = $self->couch_request(GET => $db . '/' . $id);	
	my $response = decode_json($doc);
	if ($response->{'_id'} eq $id) { return $response; } # if we got the doc, return it
	
	fail("Error Getting $db/$id", $response); # otherwise, fail

}

################
### GET VIEW ###
################

sub get_view:method {

	my ($self, $view) = @_;

	unless($view) { fail("get_doc requires a view", "view=$view"); }

	my $doc = $self->couch_request(GET => $view);	
	my $response = decode_json($doc);
	
	return $response;

}

###############
### NEW DOC ###
###############

sub new_doc:method {

	my ($self, $db, $perl_doc) = @_;
	
	unless($db =~ m/^([_a-zA-Z0-9]+)$/) { fail("new_doc requires a DB name"); }
	unless(ref($perl_doc) eq 'HASH') { fail("new_doc requires a HASHREF of data"); }
	
	my $json = encode_json($perl_doc);
	my $id = $self->next_id();
	my $result = $self->couch_request(PUT => "$db/$id", $json);
	
	my $response = decode_json($result);
	if ($response->{ok} and $response->{id}) { return $response->{id}; }
	
	fail("error Creating $db/$id", $response, $perl_doc);

}

################
### SAVE DOC ###
################

sub save_doc:method {

	my ($self, $db, $perl_doc, $conflict_ignore) = @_;

	unless($db =~ m/^([_a-zA-Z0-9]+)$/) { fail("save_doc requires a DB name"); }
	unless(ref($perl_doc) eq 'HASH') { fail("save_doc requires a HASHREF of data"); }
	
	my $id = $perl_doc->{'_id'};
	unless ($id) { fail("save_doc requires adoc with an _id", $perl_doc); }

	my $json = encode_json($perl_doc);
	my $result = $self->couch_request(PUT => "$db/$id", $json);

	my $response = decode_json($result);
	if ($response->{ok} and $response->{id}) { return $response->{id}; }
	
	# Auto-resolve conflicts
	if ($conflict_ignore and ($response->{error} eq 'conflict')) {
		if ($conflict_ignore > 9) { fail("Auto conflict resolution failure!", $response, $perl_doc); }
		my $new_doc = $self->get_doc($db, $id);
		$perl_doc->{'_rev'} = $new_doc->{'_rev'}; # Just grab the version from the newer document :o
		my $rescued_id = $self->save_doc($db, $perl_doc, $conflict_ignore + 1);
		return $rescued_id;
	}
	
	fail("Error saving $db/$id", $response, $perl_doc);
	
}

##################
### UPDATE DOC ###
##################

# Load the doc, apply the code ref to it, save it

sub update_doc:method {

	my ($self, $db, $id, $code_ref) = @_;

	unless($db =~ m/^([_a-zA-Z0-9]+)$/)     { fail("update_doc requires a DB name"); }
	unless($id =~ m/^([_a-zA-Z0-9]+)$/)     { fail("update_doc requires a doc ID"); }
	unless(ref($code_ref) eq 'CODE') { fail("update_doc requires a code ref!"); }

	for my $tries (1..10) {
	
		# load the document
		my $doc = $self->couch_request(GET => $db . '/' . $id);	
		my $perl_doc = decode_json($doc);
		if ($perl_doc->{'_id'} ne $id) { fail('couch update_doc (doc not found)', $id); }
		
		# Apply the code reference
		eval { $code_ref->($perl_doc) };
		if ($@) { fail('couch update_doc Code Ref Failed!', $@); }
		
		# try to save it
		my $json = encode_json($perl_doc);
		my $result = $self->couch_request(PUT => "$db/$id", $json);
		my $response = decode_json($result);
		
		# OKEY DOKEY
		
		if ($response->{ok} and $response->{id}) {
			$esponse->{updated_doc} = $perl_doc;
			return $response->{id};
		}
		
		# TRY AGAIN
		if ($response->{error} eq 'conflict') { next; }
		
		# FAILURE
		fail("error updating $db/$id", $response);

	}
	
	fail("Conflict not resolved updating $db/$id after 10 tries!");
	
}

##################
### DELETE DOC ###
##################

sub delete_doc:method {

	my ($self, $db, $id, $revision) = @_;

	unless($db =~ m/^([_a-zA-Z0-9]+)$/) { fail("delete_doc requires a DB name"); }
	unless($id =~ m/^([_a-zA-Z0-9]+)$/) { fail("delete_doc requires a doc ID"); }
	unless($revision) { fail("delete_doc requires a revision"); }

	my $doc = $self->couch_request(DELETE => $db . '/' . $id . '?rev=' . $revision);
	my $perl_doc = decode_json($doc);
	return $perl_doc;

}


###############
### next_id ###
###############

# Get the next available ID, init if needed

sub next_id:method {

	my ($self) = @_;
	
	if ($self->{timer_id}) { $self->{timer_id} += 1; }
	else { $self->{timer_id} = POSIX::floor(Time::HiRes::time() * 4) - $epoch; }
		
	my $next_id = $self->{machine_id} . $self->{process_id} . base62_encode($self->{timer_id}, 8);
	
	return $next_id;
	
}

#####################
### COUCH REQUEST ###
#####################

# A helper for couch requests

sub couch_request:method {

	my ($self, $method, $uri, $post_content) = @_;
	
	my $full_uri = $self->{couch_url} . $uri;
	my $req;
	
	unless ($self->{lwp_agent}) { $self->{lwp_agent} = LWP::UserAgent->new('COUCHY'); }
	
	if (defined $post_content) {
		$req = HTTP::Request->new( $method, $full_uri, undef, $post_content );
		$req->header('Content-Type' => 'application/json');
	}
	
	else {
		$req = HTTP::Request->new( $method, $full_uri );
	}
	
	my $response = $self->{lwp_agent}->request($req);
	
	if ($response->is_success)       { return $response->content; }
	elsif ($response->code() == 404) { return $response->content(); } # Missing doc
	elsif ($response->code() == 409) { return $response->content(); } # Conflict
  else { fail('COUCHDB: ' . $response->status_line . ":" . $response->content, $full_uri, $post_content); }
	
}


######################
### BASE 6 ENCODER ###
######################

sub base62_encode {

	my ($number, $padding) = @_;
	
	my $encoded = '';
	while ($number > 62) {
		my $remainder = $number % 62;
		$encoded = substr($base62, $remainder, 1) . $encoded;
		$number = POSIX::floor($number / 62);
	}
	
	$encoded = substr($base62, $number, 1) . $encoded;
	
	if ($padding) {
		if (length($encoded) < $padding) {
			$encoded = (substr($base62, 0, 1) x ($padding - length($encoded))) . $encoded;
		}
		elsif (length($encoded) > $padding) {
			$encoded = substr($encoded, -$padding);
		}
	}
	
	return $encoded;

}




1; # This is a lib, return 1

