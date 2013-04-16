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

package LabZero::Sql;

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

use Lab01::Core::Catcher;
use Lab01::Core::Formato;

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
		die "Database connection failed: $DBI::errstr";
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

=head2 set_sequence_generator($sequence_generator)

Provides the SQLSequenceGenerator to be used in $sql->insert

=cut

sub set_sequence_generator {
	my ($self, $sequence_generator) = @_;
	
	$self->{sequence_generator} = $sequence_generator;
}

=head2 my $sequence_generator = get_sequence_generator()

Used to get the SQLSequenceGenerator back from the connection

=cut

sub get_sequence_generator:method {

	my ($self) = @_;
	
	unless ($self->{sequence_generator}) {
		die "You must set the sequence generator before you get it!";
	}
	
	return $self->{sequence_generator};
	
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
	
     [QUERY] $Formato{aw70_12}{$query}
    [PARAMS] $Formato{aw70_12}{$params}
    [RESULT] $Formato{aw70_12}{$error_msg}
   [ERROR #] $error_code
     [EXTRA] $extra
";
	
	foreach my $key (keys %$self) {
		
		my $value = $self->{$key};
	
		if ($key eq 'connection') { next; }
		#UNCOMMENT FOR CMDLIST: if ($key eq 'cmd_list') { next; }
		if ($key eq 'idle_since') { $value = $Formato{t0}{$value}; }
		my $keyname = uc($key);
		$message .= $Formato{a0_12}{"[$keyname]"} . " $value\n";
		
	}

	foreach my $key (keys %{$self->{connection}}) {
		my $keyname = uc($key);
		$message .= $Formato{a0_12}{"[$keyname]"} . " $self->{$key}\n";
	}
	$message .= $Formato{a0_12}{"[current_time]"} . " $Formato{t0}{time()}\n";
	my $elap = time() - $self->{idle_since};
	$message .= $Formato{a0_12}{"[elapsed]"} . " $Formato{t6}{$elap}\n";
	#UNCOMMENT FOR CMDLIST: $message .= "Commandlist: \n$self->{cmd_list}";

	$message .= "\nCall stack trace for $subroutine\n";
	
	die($message);

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
	$self->{idle_since} = time();
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
	$self->{idle_since} = time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "exec:$sql_command\n";
	
	my $query = $self->{connection}->prepare_cached($sql_command);
	
	my $rows_affected = $query->execute(@data)
		or $self->error($sql_command, Dumper(\@data));

	$query->finish;
	
	# profiling information
	$self->{last_operation_length} = Time::HiRes::time() - $start_time;
	$self->{last_query} = $sql_command;
	if (@data) { $self->{last_query} .= ' : ' . join(', ', map { "'$_'" } @data); }
	
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
	$self->{idle_since} = time();
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
	$self->{idle_since} = time();
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

	return \@array_result;
	
}

=head2 eval_hash($query_string)

Evaluate a query string and return a hash such that
the first returned column is the key and the second
returned column is the value.

=cut

sub eval_hash:method {
	my ($self, $query_string, @data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}

	# profiling information
	my $start_time = Time::HiRes::time();
	$self->{idle_since} = time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "eval:$query_string\n";

	# prepare the query
	my $query = $self->{connection}->prepare_cached($query_string);
	
	# execute it
	$query->execute(@data)
		or $self->error($query_string);

	# look for too many columns in the result
	
	my $column_count = scalar(@{$query->{NAME}}) + 0;
	
	if ($column_count != 2) {
		$self->error($query_string, Dumper(\@data), "\nQueries used with this function must return exactly two columns.\nYour query returned $column_count.");
	}

	my %hash_result;
	
	# Grab them and pushem 1 by one
	# benchmarks indicate this is FASTER than using
	# fetchall_arrayref([0]) and then using a MAP
	# to turn it into an array of scalars
	
	while(my $row = $query->fetchrow_arrayref()) {
		$hash_result{ $row->[0] } = $row->[1];
	}
	
	$query->finish;
	
	# profiling information
	$self->{last_operation_length} = Time::HiRes::time() - $start_time;
	$self->{last_query} = $query_string;
	if (@data) { $self->{last_query} .= ' : ' . join(', ', map { "'$_'" } @data); }
	
	# return a pointer to the result

	return \%hash_result;
	
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
	$self->{idle_since} = time();
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

			return $firstvalue;
		
		}
	
	# if we gots no results, return an empty array
	
	} else {
	
		$query->finish;
		
		# profiling information
		$self->{last_operation_length} = Time::HiRes::time() - $start_time;
		$self->{last_query} = $query_string;
		if (@data) { $self->{last_query} .= ' : ' . join(', ', map { "'$_'" } @data); }
	
		return;
		
	}
	
	die "eval_quick: unexpected failure!";
	
}

=head2 eval_single($query_string)

Returns the values of the first row as
reference to a hash

=cut

sub eval_single:method {

	warn "Sql->eval_single() is deprecated! Please use eval_row (which is the same function, anyway)";

	return (shift)->eval_row(@_);
	
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
	$self->{idle_since} = time();
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
		
		return $row_ref;
	
	# if we gots no results, return an emptiness as
	# vast as the void of space
	
	} else {
	
		$query->finish;
		
		# profiling information
		
		$self->{last_operation_length} = Time::HiRes::time() - $start_time;
		$self->{last_query} = $query_string;
		if (@data) { $self->{last_query} .= ' : ' . join(', ', map { "'$_'" } @data); }
	
		return;
		
	}

	die "eval_single: unexpected failure!";
	
}


=head2 table_sequence_init($table)

A delegator function that calls the sequence init for the specified table.

=cut

sub table_sequence_init:method {

	my ($self, $table) = @_;

	my $result = $self->{sequence_generator}->sequence_init("sql_$table");
	return $result;

}


=head2 insert($table, %values)

Insert a new row into the table, using magic
rec number allocation and quoting values, etc

example: 

	$sql->insert('table_name', some_column => $some_value);
	$sql->insert('table_name', crazy_date_field => ['now()']);
	
=cut

sub insert:method {

	my ($self, $table, %data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}
	
	# profiling information
	my $start_time = Time::HiRes::time();
	$self->{idle_since} = time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "insert:$table\n";

	# make sure we have a sequence generator
	if (not defined $self->{sequence_generator}) {
		die "cannot insert into table $table, no sequence generator provided";
	}
	
	# allocate a new id number
	
	my $id;
	
	if (exists($data{id})) {
		$id = $data{id};
	}
	else {
		
		eval {
			$id = $self->{sequence_generator}->next_value("sql_$table");
		};
		
		if ($@) {
		
			my $error = $@;
			$error =~ s/\s+$//s;
			
			$self->error("\$id = \$self->{sequence_generator}->next_value(sql_$table, \$self);", undef, qq{
	* Error obtaining unique sequence ID for "$table"
	* $error
	});
	
		}
	
		$data{id} = $id;
	
	}
			
	# form an insert string that creates this record
	
	my @insert;
	my @insert_data;
	
	unless(exists($data{created})) { push @insert, "created=UNIX_TIMESTAMP()"; }
	
	foreach my $column (keys %data) {
		my $expr;
		
		# if the key looks like this: ['some crazy expr using ?', $some data]
		# then inster raw SQL instead of a value
		
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
	$self->{last_query} = "INSERTED row $id into table $table";
	
	# return the row ID

	return $id;
	
}

=head2 insert_flex($table, %values)

Inserts a new row into a table without any magic
columns. It's a little boring, but it works.

example: 

	$sql->insert_flex('table_name', some_column => $some_value);

=cut

sub insert_any:method {

	my ($self, $table, %data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}
	
	# profiling information
	my $start_time = Time::HiRes::time();
	$self->{idle_since} = time();
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
	
	return undef;
}

sub insert2 {
	my ($self, $table, %data) = @_;
	
	# USE INSERT_ANY TO INSERT A ROW
	$self->insert_any($table, %data);
	
	# NOW SELECT THE LAST INSERT ID
	my $id = $self->eval_quick("select last_insert_id()");
	
	# AND RETURN IT
	return $id;
}

=head2 update($table, $id, %values)

Insert a new row into the table, using magic
rec number allocation and quoting values, etc

example: 

	$sql->update('table_name', $id, some_column => $new_value);

=cut

sub update:method {

	my $call = Dumper(\@_);
	my ($self, $table, $id, %data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}

	# profiling information
	my $start_time = Time::HiRes::time();
	$self->{idle_since} = time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "update:$table\n";

	# make sure there is a valid $id
	
	unless ($id > 0) {
		die "\$sql->update: Invalid id: '$id' - Usage: update($table, $id, %values)";
	}

	# don't allow the ID to be changed
	
	if (exists($data{id})) {
	
		# if it's blank 
	
		if (($data{id} == $id) or ($data{id} eq '')) {
			
			delete($data{id});
		
		} else {
			
			die "\$sql->update: Illegal attempt to change id from $id to $data{id} using update";
			
		}
			
	}
	
	# don't allow the created to be changed
	
	if (exists($data{created})) {
		die "\$sql->update: Illegal attempt to change created date";
	}
		
	# form an insert string that updates this record
	
	my @update;
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
		
		push @update, "$column = $expr";
	
		# push @update, $column . '=?';
		# unless(defined($data{$column})) { $data{$column} = ''; }
		# push @insert_data, $data{$column}
	}
	
	my $update_statement = "update $table set " . join(", ", @update) . " where id=?";
	push @insert_data, $id;
	
	# prepare the query
	my $query = $self->{connection}->prepare($update_statement);
	
	my $rows_affected = $query->execute(@insert_data);
	
	unless ($rows_affected) {
		$self->error($update_statement, Dumper(\@insert_data), '', $call);
	}
	
	$query->finish;

	# profiling information
	$self->{last_operation_length} = Time::HiRes::time() - $start_time;
	$self->{last_query} = "UPDATED row $id in table $table";
	
	# return the row ID

	if ($rows_affected == 1) {
	
		return 1;
	
	} elsif ($rows_affected == 0) {
		
		# THIS COULD MEAN THAT WE DIDN'T MAKE CHANGES (BUT THE ROW DID EXIST)
		return 1;

		# die "\$sql->update: No row with id=$id - Update failed";
	
	} else {
	
		die "\$sql->update: ALARM CONDITION! $rows_affected rows with id=$id updated";
	
	}
	
}

=head2 update_any($table, ["userid = ?", $userid], %values)

updates any single record. Works on any table, even if
it does not conform to the lab-01 spec (ie you can use any key, or even
multiple keys)


example: 

	$sql->update_any('table_name', ["key_column = ?", $key_value], some_column => $new_value);
	$sql->update_any('table_name', ["key_column1 = ? and key_column2=?", $key_value1, $key_value2], some_column => $new_value);

=cut

sub update_any:method {

	my $call = Dumper(\@_);
	my ($self, $table, $where_ref, %data) = @_;

	if ((time() - $self->{idle_since}) > $timeout) {
		$self->check_connection();
	}

	# profiling information
	my $start_time = Time::HiRes::time();
	$self->{idle_since} = time();
	#UNCOMMENT FOR CMDLIST: $self->{cmd_list}  .= "update:$table\n";

	# make sure there is a valid where ref
	
	unless (ref($where_ref) eq 'ARRAY') {
		die "\$sql->update_any must provide an array ref for where clause";
	}
		
	# form an insert string that updates this record
	
	my @update;
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
		
		push @update, "$column = $expr";
	
		# push @update, $column . '=?';
		# unless(defined($data{$column})) { $data{$column} = ''; }
		# push @insert_data, $data{$column}
	}
	
	my @where_parts = @{$where_ref};
	my $where_clause = shift @where_parts;
	
	if ($where_clause eq '') {
		die "invalid where clause";
	}
	
	my $update_statement = "update $table set " . join(", ", @update) . " where $where_clause limit 1";
	push @insert_data, @where_parts;
	
	# prepare the query
	my $query = $self->{connection}->prepare($update_statement);
	
	my $rows_affected = $query->execute(@insert_data);
	
	unless (defined $rows_affected) {
		$self->error($update_statement, Dumper(\@insert_data), '', $call);
	}
	
	$query->finish;

	# profiling information
	$self->{last_operation_length} = Time::HiRes::time() - $start_time;
	$self->{last_query} = "UPDATED row in table $table";
	
	# return the row ID

	if ($rows_affected == 1) {
	
		return 1;
	
	} elsif ($rows_affected == 0) {
		
		# THIS COULD MEAN THAT WE DIDN'T MAKE CHANGES (BUT THE ROW DID EXIST)
		return 1;

		# die "\$sql->update: No row with id=$id - Update failed";
	
	} else {
	
		die "\$sql->update_any: ALARM CONDITION! $rows_affected rows";
	
	}
	
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

