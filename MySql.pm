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

package LabZero::MySql;

=head1 Sql

An OO library for socket or IP based SQL access
This library knows how to connect to a variety of
SQL servers.

=head2 new()

new() is a factory which returns an appropriate
connection based on the specified SQL server name.
If the server you specified already has a
connection open to it, you will receive a copy of
the reference to that server.

=head2 private()

If you must have your very own connection (not
shared with other packages) you can use private()
for a private connection to the server, in which
case it will always give you your very own
connection, no matter how many are already open to
that server.

=head2 clear()

In order to make transactional locking in this
library work with MOD_PERL, you should call
Lab01::SQL::clear() during the cleanup phase of
your mod_perl handler. If you fail to do this,
your connection to the SLQ server will remain
open, and thus any SQL locks that are in place may not be
automatically cleared. Additionally, threads left
open will time out after a number of hours, and
thus be unavailable.

=cut

use strict;

use DBI;
use Time::HiRes;
use Data::Dumper;

use LabZero::Fail;

our $timeout = 60 * 60;

=head2 new($url, $username, $password)

Creates a new SQL object with it's own connection. You
generally want to have some sort of connection caching/pooling,
so use the SQLFactory.

=cut

sub new:method {

	my ($class, $url, $username, $password) = @_;
				
	# connect to the server
	
	my $connection = DBI->connect($url, $username, $password, {mysql_auto_reconnect => 0});
	
	unless ($connection) {
		fail("Database connection failed: $DBI::errstr");
	}
	
	$connection->{RaiseError} = 0;
	$connection->{PrintError} = 0;

	# make an object
	
	my ($package, $filename, $line) = caller;
	
	my %connection_atrributes = (
		connection => $connection,
		connected => 1,
		opener => "$package ($filename, line $line)",
		idle_since => time(),
		sequence_generator => undef,
		#UNCOMMENT FOR CMDLIST: cmd_list   => "created:\n",
	);
	
	return bless \%connection_atrributes, $class;	
}


=head2 disconnect($caller_name)

$caller_name is completely optional, in case
an intermediary method wants to make itself
transparent in the call stack. If $caller_name
is not specified, it will be determined for you.

Disconnects the object without destroying it.
This is useful for error handling, so that we
can note WHO closed a shared connection in case
someone tried to use it after it had been closed.

In some cases, a cleanup sort of routine might
want to explicitly close the connections and
remove them from %open_connections. However, we
cannot explicitly delete the object if some other
package happens to have a reference to it still
hanging around.

=cut

sub disconnect:method {
	
	my ($self, $caller_name) = @_;
	
	# note who disconnected the thread
	
	if ($caller_name eq '') {
		my ($package, $filename, $line) = caller;
		$caller_name = "$package ($filename, line $line)";
	}
		
	# disconnect it and mark the connection closed
	
	$self->{connected} = 0;	
	$self->{connection}->disconnect();
	$self->{closer} = $caller_name;

}


=head2 DESTROY

The default destructor nicely disconnects before
disposing of the object, if the object has
not already been disconnected.

Note that this only gets called by PERL, not by
a user.

=cut

sub DESTROY {
	
	my ($self) = @_;
	
	if ($self->{connected}) {
	
		if (defined($self->{connection})) {
			$self->{connection}->disconnect();
		}
	
	}

}

=head2 check_connection()

check_connection gets called internally by
various function whenever it has been an hour
or more since the open connection was used.
If the server has timed out our connection,
we close it so it won't stay in the cache.
This isn't probably the best bahavior, but
it _is_ better than keeping the busted connection
around.

=cut

sub check_connection:method {
	
	my ($self) = @_;
	
	# Try a test query!
	
	# prepare the query
	my $query = $self->{connection}->prepare('select 1+2');
	
	# execute it
	my $ok = $query->execute();
	
	unless ($ok) {
	
		my $error_code = $self->{connection}->err();
		warn "Check connection detected a possibly busted connection... closing connection - err # $error_code";
		$self->disconnect;
		$self->error('select 1+2');
		
	}
	
	$self->{idle_since} = time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "checked:\n";

}


=head2 error()

This method is only called internally. It is the
default handler for query errors.

=cut

sub error:method {
	
	my ($self, $query, $params, $custom, $extra) = @_;
	
	# see what error the database handle contains
	
	my $error_code = $self->{connection}->err();
	my $error_msg = $self->{connection}->errstr();
	
	# note the name of our caller
	
	my ($package, $filename, $line, $subroutine) = caller(1); 
	
	# print a handy, friendly error with lots of debugging info
	
	my $message = "$subroutine generated an SQL error$custom
	
     [QUERY] $query
    [PARAMS] $params
    [RESULT] $error_msg
   [ERROR #] $error_code
     [EXTRA] $extra
";
	
	foreach my $key (keys %$self) {
		
		my $value = $self->{$key};
	
		if ($key eq 'connection') { next; }
		#UNCOMMENT FOR CMDLIST: if ($key eq 'cmd_list') { next; }
		if ($key eq 'idle_since') { $value = localtime($value); }
		my $keyname = uc($key);
		$message .= "[$keyname] $value\n";
		
	}

	foreach my $key (keys %{$self->{connection}}) {
		my $keyname = uc($key);
		$message .= "[$keyname] $self->{$key}\n";
	}
	$message .= "[current_time] " . localtime(time()) . "\n";
	my $elap = time() - $self->{idle_since};
	$message .= "[elapsed] $elap sec\n";
	#UNCOMMENT FOR CMDLIST: $message .= "Commandlist: \n$self->{cmd_list}";

	$message .= "\nCall stack trace for $subroutine\n";
	
	fail($message);

}

=head2 time()

Returns the unix timestamp according to the SQL
server.

In environments where multiple servers share an SQL 
server, this allows perfect synchronization of
time between machines.

=cut

sub time:method {

	my ($self) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}

	# profiling information
	my $start_time = Time::HiRes::time();
	
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "time:\n";
	
	my $query_string = 'select UNIX_TIMESTAMP() AS the_time';
	my $query = $self->{connection}->prepare_cached($query_string);
	
	$query->execute()
		or $self->error($query_string);

	my $quick_result = $query->fetchrow_hashref();
	my $server_time = $quick_result->{the_time};

	$query->finish;

	# profiling information
	$self->{last_operation_length} = Time::HiRes::time() - $start_time;
	$self->{last_query} = $query_string;

	$self->{idle_since} = time();
	return $server_time;
	
}

=head2 exec($sql_command)

Execute an SQL command that returns no result.

=cut

sub exec:method {

	my ($self, $sql_command, @data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}

	# profiling information
	my $start_time = Time::HiRes::time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "exec:$sql_command\n";
	
	my $query = $self->{connection}->prepare_cached($sql_command);
	
	my $rows_affected = $query->execute(@data)
		or $self->error($sql_command, Dumper(\@data));

	$query->finish;
	
	# profiling information
	$self->{last_operation_length} = Time::HiRes::time() - $start_time;
	$self->{last_query} = $sql_command;
	if (@data) { $self->{last_query} .= ' : ' . join(', ', map { "'$_'" } @data); }
	
	$self->{idle_since} = time();
	return $rows_affected + 0;
	
}


=head2 eval($query_string)

Evaluate a query string and return the results

=cut

sub eval:method {

	my ($self, $query_string, @data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}

	# profiling information
	my $start_time = Time::HiRes::time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "eval:$query_string\n";

	# prepare the query
	my $query = $self->{connection}->prepare_cached($query_string);
	
	# execute it
	$query->execute(@data)
		or $self->error($query_string, Dumper(\@data));

	# slurp it into a friendly array
	
	my $result = $query->fetchall_arrayref({});
	$query->finish;
	
	# profiling information
	$self->{last_operation_length} = Time::HiRes::time() - $start_time;
	$self->{last_query} = $query_string;
	if (@data) { $self->{last_query} .= ' : ' . join(', ', map { "'$_'" } @data); }
	
	# return a pointer to the result
	$self->{idle_since} = time();
	return $result;
	
}

=head2 eval_column($query_string)

Evaluate a query string and return an array ref of the
results of the first column for each row. Die if there
is more than 1 column.

=cut

sub eval_column:method {

	my ($self, $query_string, @data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}

	# profiling information
	my $start_time = Time::HiRes::time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "eval:$query_string\n";

	# prepare the query
	my $query = $self->{connection}->prepare_cached($query_string);
	
	# execute it
	$query->execute(@data)
		or $self->error($query_string);

	# look for too many columns in the result
	
	my $column_count = scalar(@{$query->{NAME}}) + 0;
	
	if ($column_count != 1) {
		$self->error($query_string, Dumper(\@data), "\nQueries used with this function may return only one column.\nYour query returned $column_count.");
	}

	my @array_result;
	
	# Grab them and pushem 1 by one
	# benchmarks indicate this is FASTER than using
	# fetchall_arrayref([0]) and then using a MAP
	# to turn it into an array of scalars
	
	while(my $row = $query->fetchrow_arrayref()) {
		push @array_result, $row->[0];
	}
	
	$query->finish;
	
	# profiling information
	$self->{last_operation_length} = Time::HiRes::time() - $start_time;
	$self->{last_query} = $query_string;
	if (@data) { $self->{last_query} .= ' : ' . join(', ', map { "'$_'" } @data); }
	
	# return a pointer to the result
	$self->{idle_since} = time();
	return \@array_result;
	
}

=head2 eval_quick($query_string)

Returns the values of the first row as an array
or the first value in the first row as a scalar

EXAMPLES:

my $count = $sql->eval_quick("select count(*) from table_foo")

my ($min, $max) = $sql->eval_quick("select min(bar), max(bar) from table_foo")

=cut

sub eval_quick:method {

	my ($self, $query_string, @data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}

	# profiling information
	my $start_time = Time::HiRes::time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "eval_quick:$query_string\n";

	# prepare the query
	my $query = $self->{connection}->prepare_cached($query_string);
	
	# execute it
	$query->execute(@data)
		or $self->error($query_string);

	# grab the first row
		
	if(my @row = $query->fetchrow_array) {
	
		# return an array
	
		if (wantarray()) {
		
			$query->finish;
			
			# profiling information
			$self->{last_operation_length} = Time::HiRes::time() - $start_time;

			return (@row);
	
		# or return 
		
		} else {
		
			# look for too many columns in the result
	
			my $column_count = scalar(@{$query->{NAME}}) + 0;
	
			if ($column_count != 1) {
				$self->error($query_string, Dumper(\@data), "\nIn scalar context, your query may return only one column.\nYour query returned $column_count columns.");
			}
		
			my $firstvalue = shift @row;
			$query->finish;
			
			# profiling information
			$self->{last_operation_length} = Time::HiRes::time() - $start_time;
			
			$self->{idle_since} = time();
			return $firstvalue;
		
		}
	
	# if we gots no results, return an empty array
	
	} else {
	
		$query->finish;
		
		# profiling information
		$self->{last_operation_length} = Time::HiRes::time() - $start_time;
		$self->{last_query} = $query_string;
		if (@data) { $self->{last_query} .= ' : ' . join(', ', map { "'$_'" } @data); }
	
		$self->{idle_since} = time();
		return;
		
	}
	
	$self->{idle_since} = time();
	fail("eval_quick: unexpected failure!");
	
}


=head2 eval_row($query_string)

Returns the values of the first row as
reference to a hash

=cut

sub eval_row:method {

	my ($self, $query_string, @data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}

	# profiling information
	my $start_time = Time::HiRes::time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "eval_single:$query_string\n";

	# prepare the query
	my $query = $self->{connection}->prepare($query_string);
	
	my $params = join(' ', @data);
	
	# execute it
	$query->execute(@data)
		or $self->error($query_string, $params);

	# grab the first row
		
	if(my $row_ref = $query->fetchrow_hashref()) {
		
		$query->finish;
		
		# profiling information
		$self->{last_operation_length} = Time::HiRes::time() - $start_time;
		$self->{last_query} = $query_string;
		if (@data) { $self->{last_query} .= ' : ' . join(', ', map { "'$_'" } @data); }
		
		$self->{idle_since} = time();
		return $row_ref;
	
	# if we gots no results, return an emptiness as
	# vast as the void of space
	
	} else {
	
		$query->finish;
		
		# profiling information
		
		$self->{last_operation_length} = Time::HiRes::time() - $start_time;
		$self->{last_query} = $query_string;
		if (@data) { $self->{last_query} .= ' : ' . join(', ', map { "'$_'" } @data); }
		
		$self->{idle_since} = time();
		return;
		
	}

	$self->{idle_since} = time();
	fail("eval_single: unexpected failure!");
	
}


=head2 insert_any($table, %values)

Inserts a new row into a table without any magic
columns. It's a little boring, but it works.

example: 

	$sql->insert_any('table_name', some_column => $some_value);

=cut

sub insert_any:method {

	my ($self, $table, %data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}
	
	# profiling information
	my $start_time = Time::HiRes::time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "insert:$table\n";
			
	# form an insert string that creates this record
	
	my @insert;
	my @insert_data;
		
	foreach my $column (keys %data) {
		my $expr;
		if (ref $data{$column} eq 'ARRAY') {
			my @parts = @{$data{$column}};
			$expr = shift @parts;
			push @insert_data, @parts;
		}
		else {
			$expr = '?';
			push @insert_data, $data{$column};
		}
		
		push @insert, "$column = $expr";
	
		# push @insert, $column . '=?';
		# unless(defined($data{$column})) { $data{$column} = ''; }
		# push @insert_data, $data{$column};
	}
	
	my $insert_statement = "insert into $table set " . join(", ", @insert);
	
	# prepare the query
	my $query = $self->{connection}->prepare($insert_statement);
	
	# execute it
	
	my $success = $query->execute(@insert_data);
	
	unless ($success) {
		$self->error($insert_statement, Dumper(\@insert_data));
	}

	$query->finish;

	# profiling information
	$self->{last_operation_length} = Time::HiRes::time() - $start_time;
	$self->{last_query} = "INSERTED row into table $table";

	$self->{idle_since} = time();	
	return undef;
	
}


=head2 insert()

Do a regular insert on a table with an auto-update id

=cut


sub insert {

	my ($self, $table, %data) = @_;

	# USE INSERT_ANY TO INSERT A ROW
	$self->insert_any($table, %data);
	
	# NOW SELECT THE LAST INSERT ID
	my $id = $self->eval_quick("select last_insert_id()");
	
	# AND RETURN IT
	return $id;
}




=head2 benchmark()

Return the fractional length (in seconds) of the last operation

=cut

sub benchmark:method {

	my ($self) = @_;
	
	return $self->{last_operation_length};
	
}


# This is a lib, return 1

1;

