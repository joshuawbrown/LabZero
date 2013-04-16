package LabZero::GlogLite;

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

=head1 Glog Lite

GLOG is a global logging package

GLOG LITE is a version of GLOG which logs directly to the filesystem without
using the SQl server or requiring a Daemon. It's not as clean, and you may have
permissions issues with the files it creates!

It handles log rolling and all that stuff. This is a much better alternative to
using PRINT statements, and it's super easy to use.

=cut

use strict;

use POSIX qw(strftime);
use Fcntl ':flock';

use LabZero::Fail;

=head1 Lab01::Services::GlogLite->new()

Example Usage:

my $glog = Lab01::Services::GlogLite->new($log_path, $log_name);

=cut

sub new {
	my ($class, $glog_dir, $log_name, %attributes) = @_;
	
	my $self = {
		log_name       => $log_name,
		glog_directory => $glog_dir,
		%attributes,
	};
	
	return bless $self, $class;
}

sub event {
	$_[0]->glog_event('production', $_[1], $_[2]);
}

sub debug {
	$_[0]->glog_event('debug', $_[1], $_[2]);
}

sub break {
	$_[0]->glog_event('production', '___GLOG_BR___', '');
}

=head1 USAGE

Logs an event to the SQL server

Your package never calls glog_event directly, but
instead uses two functions created by glog's custom
import script:

log_event() and log_debug()

Usage Example:

my $glog = Lab01::Services::GlogLite->new($log_path, $log_name);

$glog->event( event_name => 'description');
$glog->debug( event_name => 'description');

=cut


sub glog_event {
	
	my ($self, $type, $event, $note) = @_;

	# handle environment variables LAB01_GLOG_PRINT and LAB01_GLOG_PRINTONLY
	foreach my $var (qw(LAB01_GLOG_PRINT LAB01_GLOG_PRINTONLY)) {
		if (exists($ENV{$var}) && $ENV{$var} == 1) {
			my $ev2 = $event;
			my $no2 = $note;
			if ($ev2 eq '___GLOG_BR___') { $ev2 = '-' x 15; $no2 = '-' x 40; }
			printf(STDERR "% 30s | % 10s | % 15s | %s\n", $self->{log_name}, $type, $ev2, $no2);
			return if $var eq 'LAB01_GLOG_PRINTONLY';
		}
	}
	
	my %data = (
		logfile  => $self->{log_name},
		type     => $type,
		event    => $event,
		note     => $note,
		the_time => time(),
	);

	if (ref($note) eq 'HASH') {
		
		my $align = 0;
		foreach my $column (keys %{$note}) {
			if (length($column) > $align) { $align =length($column); }
		}
	
		if ($align > 15) { $align = 15; }
		
		$data{note} = '__GLOG_BR__';
		
		foreach my $key (sort keys %{$note}) {
			my $value = $note->{$key};
			for ($value) {
				s/(\n|\r|\t)/ /g;
				s/^\s+//s;
				s/\s+$//s;
			}
			
			my $pad;
			if (length($key) < $align) { $pad = ' ' x ($align - length($key)); }
			$data{note} .= "  $key$pad : ${value}__GLOG_BR__";
		}
	
	}
	
	foreach my $column (keys %data) {
		for ($data{$column}) {
			s/\\/\\\\/g;     # Replace the backslash with two backslashes
			s/'/\\'/g;       # Escape single quotes
			s/"/\\"/g;       # Escape double quotes
			s/(\n|\r|\t)/ /g; # IGNORE line breaks (flatten to spaces)
		}
	}
	
	$self->do_glog(\%data);
	
}


### LOGGING ###

sub do_glog {

	my ($self, $entry) = @_;
	
	my $cleanup;
	my $identity = qq(stream="$entry->{logfile}", event="$entry->{event}", note="$entry->{note}");
	
	# handle malformed entries first
	
	if ($entry->{type} eq '') {
		if ($self->{fail_silently}) { return; }
		die("Missing entry type for entry in $identity");
	}
	
	elsif ($entry->{type} !~ m/^(production|debug)$/) {
		if ($self->{fail_silently}) { return; }
		die("Invalid entry type '$entry->{type}' for entry in $identity");
	}
	
	elsif ($entry->{event} eq '') {
		if ($self->{fail_silently}) { return; }
		die("Missing event name for '$entry->{type}' entry in $identity");
	}
	
	# calculate the directory path and the logfile name
	
	my $stream = $entry->{logfile};
	for ($stream) {
		s{^/}{};
		s{/$}{};
	}
	
	my $glog_dir_root = $self->{glog_directory};
	my $stream_path = "$glog_dir_root/$stream";
	
	if ($stream =~ s/[&;:\\]//g) {
		if ($self->{fail_silently}) { return; }
		die("Invalid stream '$stream_path' illegal characters in $identity");
	}
	
	my $short_stream_name = $stream;
	if ($stream =~ m{^.+/([^/]+)$}) {
		$short_stream_name = $1;
	}
	
	my $logfile_name;
	my $stamp = strftime('%Y-%m', localtime($entry->{the_time}));
	
	if ($entry->{type} eq 'production') {
		$logfile_name = "$short_stream_name.$stamp.log";
	} else {
		my $year = strftime('%Y', localtime(time()));
		$logfile_name = "debug.log";
	}
	
	my $logfile_path = "$stream_path/$logfile_name";
	unless ($self->{file_list}{$short_stream_name} eq $logfile_path) {
		$self->{file_list}{$short_stream_name} = $logfile_path;
		$cleanup = 1; # New or Changed Log File ($short_stream_name => $logfile_path)
	}
	
	### MAKE SURE THAT THE DIRECTORY EXISTS
	
	if (-e $stream_path) {
	
		unless (-d $stream_path) {
			if ($self->{fail_silently}) { return; }
			die("Invalid stream '$stream_path' - stream path is a file! Specified in '$entry->{type}' entry in $identity");
		}
	
	} else {
	
		system("mkdir -p -m0755 $stream_path");
	
		if (-d $stream_path) {
			$cleanup = 1; # New Glog created
		}
		
		else {
			if ($self->{fail_silently}) { return; }
			die("Failed to create directory for stream '$stream_path'");
		}
	
	}
	
	### OPEN THE LOGFILE, unless it is already open
	# we keep track of the last open file and keep it open, for efficiency
		
	my $open_success = open(my $log_fh, ">>$logfile_path");
	unless ($open_success) {
		if ($self->{fail_silently}) { return; }
		die("Failed to open '$logfile_path'. Error: $!\. Specified in '$entry->{type}' entry in $identity");
	}
	
	flock($log_fh, LOCK_EX);
	seek($log_fh, 0, 2);
	
	
	### LOG THE MESSAGE TO THE RIGHT FILE
	
	$entry->{event} =~ s/\s/_/g;
	
	for($entry->{note}) {
		s/\r|\n/ /g;
		s/__GLOG_BR__/\n/g;
		s/\n+$//;
	}
	
	if ($entry->{event} eq '___GLOG_BR___') { print $log_fh "\n"; }
	else {
		my $stamp = strftime('%Y-%m-%d %H:%M:%S', localtime($entry->{the_time}));
		print $log_fh "[$stamp] $entry->{event}: $entry->{note}\n";
	}
	
	flock($log_fh, LOCK_UN);
	close($log_fh);
	
	if ($cleanup) { $self->cleanup_logdir($stream_path); }

}


=head2 cleanup_logdir()

The cleanup subroutine is called once per hour and/or when the
process starts up. Its job is to archive stuff and also
to create nice friendly symbolic links in the right directory

=cut

sub cleanup_logdir {

	my ($self, $logdir) = @_;

	my $current_datestamp = strftime('%Y-%m', localtime(time()));
	
	# FIND ALL THE DIRECTORIES THAT HAVE GLOGS
	
	open(my $list, "/usr/bin/find $logdir | /usr/bin/sort |");
	
	my $latest;
	
	while (my $entry = <$list>) {
		if ($entry =~ m{^(.+)\/([^/]+\.\d\d\d\d-\d\d\.log)$}) {
			my $dir = $1;
			my $file = $2;
			$latest = $file;
		}
	}
			
	my $latest = "$logdir/$latest";
	my $symlink_file_name = "$logdir/current.log";
	
	# print "       Log Dir: $logdir\n";
	# print "Latest version: $latest\n";
	# print "  Symlink File: $symlink_file_name\n";
	
	if (-l $symlink_file_name) {
	
		my $linked_file = readlink($symlink_file_name);
		
		# replace the stale symlink
		
		if ($linked_file ne $latest) {
			
			my $did_unlink = unlink($symlink_file_name);
			
			if ($did_unlink) {
				# print "REMOVED: stale symlink $symlink_file_name\n";
			} else {
				if ($self->{fail_silently}) { return; }
				die "ERROR: failed to remove stale symlink $symlink_file_name ($!)\n";
			}
			
			my $did_relink = symlink($latest, $symlink_file_name);
			
			if ($did_relink) {
				# print "REPLACED: symlink $symlink_file_name\n";
			} else {
				if ($self->{fail_silently}) { return; }
				die "ERROR: failed to symlink $symlink_file_name to $latest ($!)\n";
			}
			
		}
		
	} else {
	
		# create a new symlink
		
			my $did_symlink = symlink($latest, $symlink_file_name);
			
			if ($did_symlink) {
				# print "CREATED: symlink for $symlink_file_name\n";
			} else {
				if ($self->{fail_silently}) { return; }
				die "ERROR: failed to symlink $symlink_file_name to $latest ($!)\n";
			}
	
	}
	
}

1;
