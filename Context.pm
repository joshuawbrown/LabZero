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

package LabZero::Context;

=head1 LabZero::Context

A Context serves as a repository for objects that are tied to directly to the
environment. I.E. SQL connection factories and logging objects. Using a Context
allows individual pieces of your application to be unaware of the details of the
deployment configuration.

This context supports the following stuff:

	CouchDB Settings
	MsgLite Settings
	MySql Connection Object
	GlogLite Object

	Generic Application Settings

This context requires two things:

(1) You must set an ENV variable called: LABZERO_CONFIG to the path of the config file

(2) The config file has to be in the place specified. It should look like this:

  # THIS IS AN EXAMPLE CONFIGURATION FILE
  
  return {
      
		mysql => {
			url      => 'DBI:mysql:mydata',
			username => 'foo',
			password => 'bar',
		},
		
		couchdb => {
			url      => '127.0.0.1',
			username => 'foo',
			password => 'bar',
		},
		
		glog => {
			glog_dir_path => '/var/log/glogs',
		},
		
		msg_lite => {
			socket_path => '/home/something/msglite.socket',
		},
		
		app => {
			my_setting => 1,
		},
		
  };

=cut

use strict;

use LabZero::Fail;

our %context_cache;

=head2 load

usage: my $context = LabZero::Context->load();
usage: my $context = LabZero::Context->load('/my/alternate/config/path');

Loads a Context for application MyApp. The Configuration file is usually 
specified in the environment variable called 'LABZERO_CONFIG'.

This constructor will cache Contexts, one per configuration/application pair.

After the app name, you may pass key/value pairs for optional behaviors. Right
now, the following optional behavior is defined:

	config_path
		The path to the config file that should be used. This will override the
		standard config file acquisition.

Config file path search :

	step 1, look in the path passed in to us by 
	
	step 2, look in the environemnt variable $ENV{LAB01_CONTEXT_CONFIG}


=cut

sub load {
	my ($class_name, $alternate_config_path) = @_;
	
	# WE HAVE TO RESOLVE THE LOCATION OF THE CONFIGURATION
	my $config_path;
	my $config;
	
	# See if the user specified it in the invocation
	if ($alternate_config_path) { $config = $alternate_config_path; }
	else { $config_path = _locate_config(); }
	
	# SEE IF WE ALREADY HAVE THIS CACHED
	my $cache_entry = $context_cache{$config_path};
	
	if (defined $cache_entry) {
		if ($cache_entry eq 'LOADING') {
			# Catch re-entrant calls, in case someone used context in the wrong place
			fail("re-entrant call to Context->load() config path '$config_path'");
		}
		else {
			# if we already have it cached, return it
			return $context_cache{$config_path};
		}
	}
	
	# PUT SOMETHING IN THE HASH SO WE CAN DETECT RE-ENTRANT CALLS
	$context_cache{$config_path} = 'LOADING';
	
	# NOW WE WANT TO RUN THE CONFIGURATION
	unless (-r $config_path) {
		fail("Missing or unreadable config file","specified config path: $config_path");
	}
	
	# SLURP IN THE CONFIGURATION FILE
	open (my $config_fh, $config_path);
	local $/ = undef;
	my $config_src = <$config_fh>;
	close $config_fh;
	
	# EVAL THE CONFIGURATION FILE
	$config = eval { return LabZero::Context::HiddenEval::eval_hidden($config_src); };
	if ($@) { fail("error evaluating configuration","config path: $config_path","Eval: $@"); }
	unless (ref($config) eq 'HASH') { fail("Config failed to return a hash","config path: $config_path"); }
	
	########################
	### CONTEXT CREATION ###
	########################

	# Oh right. This is a constructor! So let's construct.

	# MAKE OUR SELF RIGHT HERE
	
	my $this_context = {

		config_path  => $config_path,
		config       => $config, # A copy of our eval'd config for safe keeping
		
		objects      => {},
		defines      => {
			'load'          => 1,
			'put'           => 1,
			'get'           => 1,
			'define'        => 1,
		},
	};
	
	bless $this_context, $class_name;
	my %err;
	
	#######################
	### ADD SQL FACTORY ###
	#######################

	if (not ((ref($config->{mysql}) eq 'HASH') and (scalar(keys %{$config->{mysql}})))) {
		$err{mysql} = 'mySQL SUPPORT DISABLED. No entries were provided for the mysql setting.';
	}

	# Good to go, config sql. Just a stub for now
	else {
	
		require LabZero::MySql;
		our $mysql_object; # Cache and share the sql connection
	
		$this_context->define('mysql',
			sub {
				if ($err{mysql}) { fail("Fatal Error: $err{mysql}"); }
				
				# make a new SLQ object if needed
				unless ($mysql_object) {
					# Currently in lazy mode--we should check the individual params first. 
					$mysql_object = LabZero::MySql->new(
						$config->{mysql}{url},
						$config->{mysql}{username},
						$config->{mysql}{password},
					);
				}
				
				return $mysql_object;
				
			}
		);
	}

	###########################
	### ADD COUCHDB FACTORY ###
	###########################

	if (not ((ref($config->{couchdb}) eq 'HASH') and (scalar(keys %{$config->{couchdb}})))) {
		$err{couchdb} = 'couchdb SUPPORT DISABLED. No entries were provided for the couchdb setting.';
	}

	# Good to go, config couchdb.
	else {
	
		require LabZero::Couch;
		my $couch_object; # Cache and share the couch connector, for shared id generation
	
		$this_context->define('couchdb',
			sub {
				if ($err{couchdb})             { fail("Fatal Error: $err{couchdb}"); }
				if (! $config->{couchdb}{url}) { fail("Fatal Error: Missing couchdb / url setting"); }
				unless ($couch_object)  { 


					if($config->{couchdb}{username} ne ""){
						my $turl = $config->{couchdb}{url};

						$turl =~ s/http:\/\//http:\/\/$config->{couchdb}{username}:$config->{couchdb}{password}\@/;

						$couch_object = LabZero::Couch->new($turl);
					}
					else{ 
						$couch_object = LabZero::Couch->new($config->{couchdb}{url}); 
					}

				}
				return $couch_object;
			}
		);
	}
	
	#########################
	### ADD AN AUTH ENTRY ###
	#########################
	
	if (not ((ref($config->{auth}) eq 'HASH') and (scalar(keys %{$config->{auth}})))) {
		$err{auth} = 'auth SUPPORT DISABLED. No entries were provided for the auth setting.';
	}
	
	else {
	
		require LabZero::Auth;
		our $auth_object; # Cache and share the auth object
		
		$this_context->define('auth', sub {
				if ($err{auth}) 		{ fail("Fatal Error: $err{couchdb}"); }
				if ($err{couchdb})  { fail("Fatal Error: Auth Requires couch ($err{couchdb})"); }
				if (! $config->{auth}{db_name})     { fail("Fatal Error: Missing auth / db_name setting"); }
				if (! $config->{auth}{expired_url}) { fail("Fatal Error: Missing auth / expired_url setting"); }
				
				if (not $auth_object) {
					my $couch = $this_context->couchdb();
					my %params = (
						couch => $couch,
						%{$config->{auth}},
					);
					if ($config->{auth}{timeout})       { $params{timeout} = $config->{auth}{timeout}; }
					if ($config->{auth}{require_https}) { $params{require_https} = $config->{auth}{require_https}; }
					
					$auth_object = LabZero::Auth->new(%params);
				}
				
				return $auth_object;
				
			});
	}
	
	#########################
	### GLOG LITE FACTORY ###
	#########################

	if (not ((ref($config->{glog}) eq 'HASH') and (scalar(keys %{$config->{glog}})))) {
		$err{glog} = 'GLOG SUPPORT DISABLED. No entries were provided for the glog in the config.';
	}

	elsif (not $config->{glog}{glog_dir_path}) {
		$err{glog} = "GLOG SUPPORT DISABLED. No value was provided for 'glog:glog_dir_path'.";
	}

	else {
		
		require LabZero::GlogLite;
		
		my $glog_dir = $config->{glog}{glog_dir_path};
		$this_context->define('glog', sub {			
			if ($err{glog}) { fail("Fatal Error: $err{glog}"); }
			unless ($_[1]) {
				fail("Error: A log name is required to create a glog. Usage: \$context->glog('some_name')");
			}
			else { return LabZero::GlogLite->new($glog_dir, $_[1]); }
		});
		
	}

	#####################
	### TMOJO FACTORY ###
	#####################
	
	# To prevent memory leak, we just implement a singleton cache for tmojos	
		
	require LabZero::Tmojo;
	{

		my %tmojo_cache;
		
		$this_context->define('tmojo', sub {
			my (undef, $path) = @_;	
			unless ($path) {
				fail("Error: Base path is required to get a tmojo. Usage: \$context->tmojo('some_path')");
			}
			if (not $tmojo_cache{$path}) {
				$tmojo_cache{$path} = LabZero::Tmojo->new(template_dir => $path);
			}
			return $tmojo_cache{$path};
		});
	
	}


	#####################
	### MONGO FACTORY ###
	#####################
	
	# Implement a singleton cache for a mongoDB connection
		
	{

		my $mongo_obj;
		
		$this_context->define('mongo', sub {
			if (not $mongo_obj) {
			
				require MongoDB;
				
				if ($config->{mongo}) {
					$mongo_obj = MongoDB::MongoClient->new(%{$config->{mongo}});
				}
				else {
					$mongo_obj = MongoDB::MongoClient->new( timeout => 150000, query_timeout => 150000);
				}
			}
			return $mongo_obj;
		});
	
	}
	
	#################################################
	### GENERIC APP CONFIG KEYS WITH NICE FAILURE ###
	#################################################
	
	# This basically works like get but with a lot of error checking
	
	if (not (ref($config->{app}) eq 'HASH')) {
		$err{app} = 'app config SUPPORT DISABLED. No entry was provided for the app hash!';
	}	
	
	my %app_config = %{ $config->{app} }; # A shallow copy
	
	$this_context->define('app', sub {
	
		if ($err{app}) { fail("Fatal Error: $err{app}"); }
		unless ($_[1]) { fail("Error: Specify the key(s) to get! Usage: \$context->app('DemoApp', 'lib_root')"); }
		
		# Quick hash traversal
		my $target = \%app_config;
		my $history;
		foreach my $param (1..scalar(@_)-1) {
			my $next_key = $_[$param];
			my $new_node = eval { $target->{$next_key} };
			if ($@) { fling("Invalid Config Key '$next_key' (Path='$history') ($@)"); }
			$history .= "$next_key ";
			$target = $new_node;
		}
		
		if (not defined($target)) {
			fail("Empty Config Key! (Path='$history')");
		}
		
		return $target;
		
	});
	
	### SOME OTHER FACTORIES GO HERE ###
	
	# Oh yeah
	
	# CACHE THIS CONTEXT FOR THIS CONFIGURATION
	$context_cache{$config_path} = $this_context;
	
	# WE SHOULD BE DONE!
	return $this_context;
	
}

=head2 put

usage: $Context->put('sql_obj', $my_sql_obj);

For the most part, 'put' is only called in the app file. It is used to register
objects with the Context. This value will also be accessible via a method, as in
$Context->sql_obj. 'define' has higher priority than 'put' for retrieving these,
though it would be fairly bad form to name a put and a define the same thing.

=cut

sub put {
	my ($self, $name, $obj) = @_;
	
	if (exists $self->{objects}{$name}) {
		fail("context for application $self->{app_name} already contains an object named $name");
	}
	
	$self->{objects}{$name} = $obj;
	
	return $self;
}

=head2 get

usage: my $sql = $Context->get('sql_obj');

Used by application code to retrieve objects stored in the Context.

=cut

sub get {
	my ($self, $name) = @_;
	
	unless (exists $self->{objects}{$name}) {
		fail("context for application $self->{app_name} does not contain an object named '$name'");
	}
	
	return $self->{objects}{$name};
}

=head2 define

usage: $Context->define('method_name', sub { ... });

This is used in the application script to define a custom method on the Context.
This allows you to shortcut through factories and all sorts of cool stuff.

=cut

sub define {
	my ($self, $name, $sub) = @_;
	
	if ($name !~ /^[a-zA-Z]\w+/) {
		fail("illegal name for define: $name]");
	}
	
	if (defined $self->{defines}{$name}) {
		fail("not a CODE reference passed to define for name $name");
	}
	
	unless (ref($sub) eq 'CODE') {
		fail("not a CODE reference passed to define for name $name");
	}
	
	$self->{defines}{$name} = $sub;
	
	return $self;
}

=head2 AUTOLOAD

The AUTOLOAD redirects all other methods calls to those 'defined' on the
Context. If no defined object can be found, it also searches for an object
that was added with 'put'.

=cut

sub AUTOLOAD {
	return if our $AUTOLOAD =~ /::DESTROY$/;

	my ($self, @args) = @_;
	
	my ($method_name) = ($AUTOLOAD =~ /::(\w+)$/);
	
	if (defined $self->{defines}{$method_name}) {
		return $self->{defines}{$method_name}->($self, @args);
	}
	elsif (defined $self->{objects}{$method_name}) {
		return $self->{objects}{$method_name};
	}
	else {
		fail("$method_name not defined for Context");
	}
}

=head2 _locate_config

This function is used internally to locate the path of the config. Right now, it
only looks in the environment variable 'LABZERO_CONFIG'.

=cut

sub _locate_config {
	
	my $path;
		
	# STEP 2, LOOK IN THE ENVIRONMENT VARIABLE
	if ($ENV{LABZERO_CONFIG} ne '') {
		$path = $ENV{LABZERO_CONFIG};
	}
	
	if (not defined $path) {
		fail("Could not find the config. Specify the path or set the LABZERO_CONFIG environment variable.");
	}
	
	return $path;
}

=head1  LabZero::Context::HiddenEval

This clever little package defines a nice little function that 
allows us to eval source without exposing our lexical variables!

=cut

package LabZero::Context::HiddenEval;

sub eval_hidden {
	my $__result = eval($_[0]);
	if ($@) {
		die $@;
	}
	
	return $__result;
}

1;

