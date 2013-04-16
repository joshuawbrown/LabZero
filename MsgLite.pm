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

package LabZero::MsgLite;

use strict;

use IO::Socket::UNIX;
use LabZero::Fail;

use constant {
	READY_CMD     => '<',
	MESSAGE_CMD   => '>',
	QUERY_CMD     => '?',
	TIMEOUT_CMD   => '*',
	QUIT_CMD      => '.',
	ERROR_CMD     => '-',	
};

sub at_unix_socket {

	my ($class, $path) = @_;
	
	my $io_socket = IO::Socket::UNIX->new(
		Peer => $path,
		Type => SOCK_STREAM,
		Timeout => 1) || fail($!, $path);
	
	my $this = {io_socket => $io_socket};
	bless $this, $class;
	return $this;
	
}

sub io_socket {
	my ($self) = @_;	
	return $self->{io_socket};
}

sub ready {
	my ($self, $timeout, @on_addrs) = @_;
	
	my $buf = join(' ', READY_CMD, $timeout, @on_addrs) . "\r\n";
	
	$self->io_socket->print($buf)
		|| die "error writing to socket: $!";
		
	return $self->_read_message;
}

sub send {
	my ($self) = shift;
	
	my $msg;
	if (!ref($_[0])) {
		if (@_ < 3 || @_ > 4) {
			die "wrong number of arguments to send";
		}
		my $reply_addr = @_ == 4 ? $_[3] : '';
		
		$msg = LabZero::MsgLiteMessage->new({
			body       => $_[0],
			timeout    => $_[1],
			to_addr    => $_[2],
			reply_addr => $reply_addr,
		});
	}
	else {
		$msg = $_[0];
	}
	
	my $buf = join(' ', MESSAGE_CMD, bytes::length($msg->body), $msg->timeout, $msg->to_addr, $msg->reply_addr) . "\r\n";
	
	if (bytes::length($msg->body) > 0) {
		$buf .= $msg->body . "\r\n";
	}
	
	$self->io_socket->print($buf)
		|| die "error writing to socket: $!";
}

sub bounce {
	my ($self, $msg, $new_recipient) = @_;
		
	my $buf = join(' ', MESSAGE_CMD, bytes::length($msg->body), $msg->timeout, $new_recipient, $msg->reply_addr) . "\r\n";
	
	if (bytes::length($msg->body) > 0) {
		$buf .= $msg->body . "\r\n";
	}
	
	$self->io_socket->print($buf)
		|| die "error writing to socket: $!";
}


sub query {
	my ($self, $body, $timeout, $to_addr) = @_;
	
	my $buf = join(' ', QUERY_CMD, bytes::length($body), $timeout, $to_addr) . "\r\n";
	
	if (bytes::length($body) > 0) {
		$buf .= $body . "\r\n";
	}
	
	$self->io_socket->print($buf)
		|| die "error writing to socket: $!";
	
	return $self->_read_message;
}

sub quit {
	my ($self) = @_;
	
	$self->io_socket->print(QUIT_CMD . "\r\n");
	$self->io_socket->close;
}

sub _read_message {
	my ($self) = @_;
	
	local $/ = "\r\n";
	
	my $cmd_line = $self->io_socket->getline;
	chomp $cmd_line;
	
	my @command = split /\s+/, $cmd_line;
	
	return undef if $command[0] eq TIMEOUT_CMD;
	
	die $cmd_line if $command[0] eq ERROR_CMD;
	die "unexpected line from msglite server: $cmd_line" if $command[0] ne MESSAGE_CMD;
	
	if (@command < 4 || @command > 5) {
		die "unexpected number of message params from msglite server: $cmd_line";
	}
	
	my $reply_addr = @command == 5 ? $command[4] : '';
	
	my $body = '';
	if ($command[1] > 0) {
		$self->io_socket->read($body, int($command[1]))
			|| die "error reading body of message: $!";
		
		$self->io_socket->read(my $crlf, 2)
			|| die "error reading body of message: $!";
			
		if ($crlf ne "\r\n") {
			die "expected \\r\\n from msglite server after message body";
		}
	}
	
	return LabZero::MsgLiteMessage->new({
		body       => $body,
		timeout    => $command[2],
		to_addr    => $command[3],
		reply_addr => $reply_addr,
	})
	
}


package LabZero::MsgLiteMessage;

use Data::Dumper;
use LabZero::Fail;


sub new {
	my ($class, $params) = @_;
	
	foreach my $field (qw(to_addr reply_addr timeout body)) {
		unless (defined($params->{$field})) {
			fail("Missing field '$field' in constructor", Dumper($params));
		}
	}
	
	bless $params, $class;
	
	return $params;
	
};

sub to_addr {
	return $_[0]->{to_addr};
};

sub reply_addr {
	return $_[0]->{reply_addr};
};

sub timeout {
	return $_[0]->{timeout};
};

sub body {
	return $_[0]->{body};
};

1;
