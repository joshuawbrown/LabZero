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
use POSIX;

my $base62 = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
my $epoch = 5333333333;

use strict;
use base qw(Exporter);

our @EXPORT = qw(unique_keys unique_field);

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
		
		couch_url  => $couch_url,
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
### Filters ###
###############

sub _check_db {

	my ($db_name) = @_;
	unless($db_name =~ m/^([-_a-zA-Z0-9]+)$/) {
		fail('DB name ($db) required', "db=$db_name");
	}

};

sub check_id:method {

	my ($id) = @_;
	unless($id =~ m/^([-_a-zA-Z0-9\@\.\+]+)$/) {
		fail('ID ($id) required', "id=$id");
	}	
}


sub unique_keys {
	
	my %hash = map { $_ => 1 } @_;
	my @keys;
	foreach my $key (keys %hash) {
		if ($key ne '') { push @keys, $key; }
	}
	return @keys;

}

sub unique_field {
	
	my ($fieldname, $rows) = @_;
	
	if (ref($rows) ne 'ARRAY') { fail("An array ref is required for param 2", ref($rows)); }
	my %hash;
	my @unique_keys; # Preserve order
	foreach my $row (@$rows) {
		my $value;
		if (exists($row->{$fieldname})) { $value = $row->{$fieldname}; }
	  elsif ($row->{doc} and $row->{doc}{$fieldname}) { $value = $row->{doc}{$fieldname}; }
	  if (($value ne '') and not $hash{$value}) {
	  	push @unique_keys, $value;
	  	$hash{$value} = 1;
	  }
	}

	return @unique_keys;

}


###############
### DB INFO ###
###############

sub get_db_info:method {

	my ($self, $db) = @_;

	_check_db($db);

	my $doc = $self->couch_request(GET => $db);	
	my $response = decode_json($doc);
	
	if ($response->{error}) { fail("Error Getting $db", $response); }
	return $response;

}

###############
### GET DOC ###
###############

sub get_doc:method {

	my ($self, $db, $id, $missing_ok) = @_;

	_check_db($db);

	my $doc = $self->couch_request(GET => $db . '/' . $id);	
	my $response = decode_json($doc);
	
	# return doc
	if ($response->{'_id'} eq $id) { return $response; } # if we got the doc, return it
	
	# return missing
	if ($missing_ok) { return undef; }
	
	# die if no id and missing not ok
	fail("Error Getting $db/$id", $response); # otherwise, fail

}

################
### GET DOCS ###
################

sub get_docs:method {

	my ($self, $db, $ids) = @_;

	_check_db($db);
	
	if (ref($ids) ne 'ARRAY') { fail("An array ref is required for param 2", ref($ids)); }
	
	my $id_count = scalar(@$ids);

	my $id_list = { 'keys' => $ids };
	my $json = encode_json($id_list);
	my $result = $self->couch_request(POST => "$db/_all_docs?include_docs=true", $json);

	my $response = decode_json($result);

	# return doc if we got a result
	if ($response->{total_rows}) {
		my @docs = map { $_->{doc} } (@{$response->{rows}});
		return \@docs;
	}
	
	# die if no id and missing not ok
	fail("Error Getting $db bulk [$id_count keys]", $response); # otherwise, fail

}

################
### GET DOCS ###
################

sub get_view_multi:method {

	my ($self, $view, $ids) = @_;

	unless($view) { fail("get_doc requires a view", "view=$view"); }
	my $id_count = scalar(@$ids);

	my $id_list = { 'keys' => $ids };
	my $json = encode_json($id_list);
	my $result = $self->couch_request(POST => $view, $json);

	my $response = decode_json($result);

	# return doc
	if ($response->{rows}) {
	
		# Return all the response rows if no docs
		if (not $response->{rows}[0]{doc}) {
			my @docs = map { { '_key' => $_->{key}, '_value' => $_->{value}, } } (@{ $response->{rows} });
			return \@docs;
		}
	
		# Or, slup up the docs as well, if they are there
		my @docs;
		foreach my $row (@{ $response->{rows} }) {
			my $doc = $row->{doc};
			$doc->{'_key'} = $row->{key};
			$doc->{'_value'} = $row->{value};
			unshift @docs, $doc;
		}
		
		return \@docs;
		
	} # if we got a result
	
	# die if no id and missing not ok
	fail("Error Getting bulk view [$id_count keys]", $view, $response); # otherwise, fail

}

################
### GET VIEW ###
################

sub get_view:method {

	my ($self, $view) = @_;

	unless($view) { fail("get_doc requires a view", "view=$view"); }

	my $doc = $self->couch_request(GET => $view);	
	my $response = decode_json($doc);
	
	if (not $response->{rows}) { fail("Error Getting view", $view, $response); }
	
	# Return an empty array if there was nothing
	if (not scalar(@{ $response->{rows} })) { return $response->{rows}; }
	
	# Return all the response rows if no docs
	if (not $response->{rows}[0]{doc}) {
		my @docs = map { { '_key' => $_->{key}, '_value' => $_->{value}, } } (@{ $response->{rows} });
		return \@docs;
	}

	# Or, slup up the docs as well, if they are there
	my @docs;
	foreach my $row (@{ $response->{rows} }) {
		my $doc = $row->{doc};
		$doc->{'_key'} = $row->{key};
		$doc->{'_value'} = $row->{value};
		push @docs, $doc;
	}
	return \@docs;

}

###############
### NEW DOC ###
###############

sub new_doc:method {

	my ($self, $db, $perl_doc, %params) = @_;
	
	_check_db($db);
	unless(ref($perl_doc) eq 'HASH') { fail("new_doc requires a HASHREF of data"); }
	
	my $json = encode_json($perl_doc);
	my $id = $perl_doc->{'_id'} || $self->next_id();
	
	my $url = "$db/$id";
	if ($params{batch}) { $url .= "?batch=ok"; }
	my $result = $self->couch_request(PUT => $url, $json, %params);
	
	my $response = decode_json($result);
	if ($response->{ok} and $response->{id}) { return $response->{id}; }
	
	fail("error Creating $db/$id", $response, $perl_doc);

}

################
### SAVE DOC ###
################

sub put_doc:method {

	my ($self, $db, $perl_doc, $conflict_ok) = @_;

	_check_db($db);
	unless(ref($perl_doc) eq 'HASH') { fail("save_doc requires a HASHREF of data"); }
	
	my $id = $perl_doc->{'_id'};
	unless ($id) { fail("save_doc requires a doc with an _id", $perl_doc); }

	my $json = encode_json($perl_doc);
	my $result = $self->couch_request(PUT => "$db/$id", $json);

	my $response = decode_json($result);
	if ($response->{ok}) { return $response; }
	
	# fail or return on conflict
	if ($response->{error} eq 'conflict') {
		if ($conflict_ok) { return undef; }
		fail("Error putting $db/$id", $response, $perl_doc);
	}
	
}

##################
### UPDATE DOC ###
##################

# Load the doc, apply the code ref to it, save it

sub update_doc:method {

	my ($self, $db, $id, $code_ref) = @_;

	_check_db($db);
	unless(ref($code_ref) eq 'CODE') { fail("update_doc requires a code ref!"); }

	for my $tries (1..50000) {
	
		# load the document
		my $doc = $self->couch_request(GET => $db . '/' . $id);	
		my $perl_doc = decode_json($doc);
		
		# if it doesn't exist yet, let's make a new, blank one
		if ($perl_doc->{'_id'} ne $id) {
			$perl_doc = { '_id' => $id };
		}
		
		# Apply the code reference
		eval { $code_ref->($perl_doc) };
		if ($@) { fail('couch update_doc Code Ref Failed!', $@); }
		
		# try to save it
		my $json = encode_json($perl_doc);
		my $result = $self->couch_request(PUT => "$db/$id", $json);
		my $response = decode_json($result);
		
		# OKEY DOKEY
		
		if ($response->{ok} and $response->{id}) {
			$response->{updated_doc} = $perl_doc;
			return $response;
		}
		
		# TRY AGAIN
		if ($response->{error} eq 'conflict') { next; }
		
		# FAILURE
		fail("error updating $db/$id", $response);

	}
	
	fail("Conflict not resolved updating $db/$id after 100 tries!");
	
}

###################
### UPDATE DOCS ###
###################

sub update_docs:method {

	my ($self, $db, $updates) = @_;

	_check_db($db);
	
	if (ref($updates) ne 'ARRAY') { fail("An array ref is required for param 2", ref($updates)); }
	
	my $id_count = scalar(@$updates);

	my $update_list = { 'docs' => $updates };
	my $json = encode_json($update_list);
	my $result = $self->couch_request(POST => "$db/_bulk_docs", $json);

	my $response = decode_json($result);

	return $response;

}

##################
### DELETE DOC ###
##################

sub delete_doc:method {

	my ($self, $db, $id, $revision, $conflict_ok) = @_;

	_check_db($db);
	unless($revision) { fail("delete_doc requires a revision"); }

	my $response = $self->couch_request(DELETE => $db . '/' . $id . '?rev=' . $revision);

	if ($response->{ok}) { return $response; }
	
	# Auto-resolve conflicts
	if ($response->{error} eq 'conflict') {
		if ($conflict_ok) { return undef; }
		fail("Error putting $db/$id", $response);
	}


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
	
	unless ($self->{lwp_agent}) {
		my %opts = ( keep_alive => 10 );
		$self->{lwp_agent} = LWP::UserAgent->new(
			agent => 'LabZero::Couch',
			keep_alive => 1,
		);
		
	}
	
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

