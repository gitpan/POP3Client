#******************************************************************************
# $Id: POP3Client.pm,v 1.18 1998/10/01 08:15:05 ssd Exp $
#
# Description:  POP3Client module - acts as interface to POP3 server
# Author:       Sean Dowd <ssd@ticnet.com>
#
# Copyright (c) 1995,1996 Electonic Data Systems, Inc.  All rights reserved.
# This module is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
#******************************************************************************

package Mail::POP3Client;

=head1 NAME

Mail::POP3Client - Perl 5 module to talk to a POP3 (RFC1081) server

=head1 DESCRIPTION

This module implements an Object-Oriented interface to a POP3 server.
It is based on RFC1081.

=head1 USAGE

Here is a simple example to list out the headers in your remote mailbox:

  #!/usr/local/bin/perl
  
  use Mail::POP3Client;
  
  $pop = new Mail::POP3Client("me", "mypassword", "pop3.do.main");
  for ($i = 1; $i <= $pop->Count; $i++) {
  	print $pop->Head($i), "\n";
  }

=head2 POP3Client Commands

These commands are intended to make writing a POP3 client easier.
They do not necessarily map directly to POP3 commands defined in
RFC1081.  Some commands return multiple lines as an array in an array
context, but there may be missing places.

=over 10

=item I<new>

Construct a new POP3 connection with this.  You should give it at
least 2 arguments: username and password.  The next 2 optional
arguments are the POP3 host and port number.  A final fifth argument
of a positive integer enables debugging on the object (to STDERR).

=item I<Head>

Get the headers of the specified message.  Here is a simple Biff
program:

  #!/usr/local/bin/perl
  
  use Mail::POP3Client;
  
  $pop = new Mail::POP3Client("me", "mypass", "pop3.do.main");
  for ($i = 1; $i <= $pop->Count; $i++) {
  	foreach ($pop->Head($i)) {
  		/^(From|Subject): / and print $_, "\n";
  	}
  	print "\n";
  }

=item I<Body>

Get the body of the specified message.

=item I<HeadAndBody>

Get the head and body of the specified message.

=item I<Retrieve>

Same as HeadAndBody.

=item I<Delete>

Mark the specified message number as DELETED.  Becomes effective upon
QUIT.  Can be reset with a Reset message.

=item I<Connect>

Start the connection to the POP3 server.  You can pass in the host and
port.

=item I<Close>

Close the connection gracefully.  POP3 says this will perform any
pending deletes on the server.

=item I<Alive>

Return true or false on whether the connection is active.

=item I<Socket>

Return the file descriptor for the socket.

=item I<Size>

Set/Return the size of the remote mailbox.  Set by POPStat.

=item I<Count>

Set/Return the number of remote messages.  Set during Login.

=item I<Message>

The last status message received from the server.

=item I<State>

The internal state of the connection: DEAD, AUTHORIZATION, TRANSACTION.

=item I<POPStat>

Return the results of a POP3 STAT command.  Sets the size of the
mailbox.

=item I<List>

Return a list of sizes of each message.

=item I<Last>

Return the number of the last message, retrieved from the server.

=item I<Reset>

Tell the server to unmark any message marked for deletion.

=item I<User>

Set/Return the current user name.

=item I<Pass>

Set/Return the current user name.

=item I<Login>

Attempt to login to the server connection.

=item I<Host>

Set/Return the current host.

=item I<Port>

Set/Return the current port number.

=head1 AUTHOR

Sean Dowd <ssd@ticnet.com>

=head1 COPYRIGHT

Copyright (c) 1995,1996 Electonic Data Systems, Inc.  All rights reserved.
This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 CREDITS

Based loosely on News::NNTPClient by Rodger Anderson
<rodger@boi.hp.com>.

=cut

#******************************************************************************
#* Other packages, globals, etc.
#******************************************************************************

require 5.000;

use Carp;
use Socket qw(PF_INET SOCK_STREAM AF_INET);

$sockaddr = 'S n a4 x8';      # shouldn't this be in Socket.pm?
$fhcnt = 0;                   # for creating unique filehandles

$ID =q( $Id: POP3Client.pm,v 1.18 1998/10/01 08:15:05 ssd Exp $ );
$VERSION = substr q$Revision: 1.18 $, 10;

#******************************************************************************
#* constructor
#******************************************************************************
sub new
{
	my $name = shift;
	my $user = shift;
	my $pass = shift;
	my $host = shift || "pop";
	my $port = shift || getservbyname("pop3", "tcp") || 110;
	my $debug = shift || 0;

    my $me = bless {
		DEBUG => $debug,
		SOCK => $name . "::SOCK" . $fhcnt++,
		SERVER => $host,
		PORT => $port,
		USER => $user,
		PASS => $pass,
		COUNT => -1,
		SIZE => -1,
		ADDR => "",
		STATE => 'DEAD',
		MESG => 'OK',
		EOL => "\015\012",
	}, $name;

	if ($me->User($user) and $me->Pass($pass) and 
		$me->Host($host) and $me->Port($port)) {
		$me->Connect();
	}

	$me;

} # end new

#******************************************************************************
#* Is the socket alive?
#******************************************************************************
sub Version {
	return $VERSION;
}

#******************************************************************************
#* Is the socket alive?
#******************************************************************************
sub Alive
{
    my $me = shift;
	$me->State =~ /^AUTHORIZATION$|^TRANSACTION$/i;
} # end Alive

#******************************************************************************
#* What's the frequency Kenneth?
#******************************************************************************
sub State
{
    my $me = shift;
	my $stat = shift or return $me->{STATE};
	$me->{STATE} = $stat;
} # end Stat

#******************************************************************************
#* Got anything to say?
#******************************************************************************
sub Message
{
    my $me = shift;
	my $msg = shift or return $me->{MESG};
	$me->{MESG} = $msg;
} # end Message

#******************************************************************************
#* set/query debugging
#******************************************************************************
sub Debug
{
    my $me = shift;
	my $debug = shift or return $me->{DEBUG};
	$me->{DEBUG} = $debug;
    
} # end Debug

#******************************************************************************
#* set/query the port number
#******************************************************************************
sub Port
{
    my $me = shift;
	my $port = shift or return $me->{PORT};

	$me->{PORT} = $port;

} # end port

#******************************************************************************
#* set/query the host
#******************************************************************************
sub Host
{
    my $me = shift;
	my $host = shift or return $me->{HOST};

    # Get address.
	if ($host =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
		$addr = pack('C4', $1, $2, $3, $4);
    } else {
		$addr = gethostbyname ($host) or
			$me->Message("Could not gethostybyname: $host, $!") and return;
	}

    # Get fully qualified domain name
    my $tmp = gethostbyaddr ($addr, AF_INET) or
		$me->Message("Could not gethostbyaddr: $host, $!") and return;

    $me->{ADDR} = $addr;
    $me->{HOST} = $tmp;
	1;
} # end host

#******************************************************************************
#* query the socket to use as a file handle
#******************************************************************************
sub Socket {
	my $me = shift;
	return $me->{'SOCK'};
}

#******************************************************************************
#* set/query the USER
#******************************************************************************
sub User
{
	my $me = shift;
	my $user = shift or return $me->{USER};
	$me->{USER} = $user;

} # end User

#******************************************************************************
#* set/query the password
#******************************************************************************
sub Pass
{
	my $me = shift;
	my $pass = shift or return $me->{PASS};
	$me->{PASS} = $pass;
    
} # end Pass

#******************************************************************************
#* 
#******************************************************************************
sub Count
{
	my $me = shift;
	my $c = shift;
	if (defined $c and length($c) > 0) {
		$me->{COUNT} = $c;
	} else {
		return $me->{COUNT};
	}
    
} # end Count

#******************************************************************************
#* set/query the size of the mailbox
#******************************************************************************
sub Size
{
	my $me = shift;
	my $c = shift;
	if (defined $c and length($c) > 0) {
		$me->{SIZE} = $c;
	} else {
		return $me->{SIZE};
	}
    
} # end Size

#******************************************************************************
#* 
#******************************************************************************
sub EOL {
    my $me = shift;
	return $me->{'EOL'};
}

#******************************************************************************
#* 
#******************************************************************************
sub Close
{
	my $me = shift;
	if ($me->Alive()) {
		$s = $me->{SOCK};
		print $s "QUIT", $me->EOL;
		shutdown($me->{SOCK}, 2) or $me->Message("shutdown failed: $!") and return 0;
		close $me->{SOCK};
		$me->State('DEAD');
	}
	1;
} # end Close

#******************************************************************************
#* 
#******************************************************************************
sub DESTROY
{
    my $me = shift;
	$me->Close;
} # end DESTROY


#******************************************************************************
#* Connect to the specified POP server
#******************************************************************************
sub Connect
{
	my ($me, $host, $port) = @_;

	$host and $me->Host($host);
	$port and $me->Port($port);

	my $s = $me->{SOCK};
	if (defined fileno $s) {
		# close and reopen...
		$me->Close;
	}

	socket($s, PF_INET, SOCK_STREAM, getprotobyname("tcp") || 6) or
		$me->Message("could not open socket: $!") and
			return 0;
	connect($s, pack($sockaddr, AF_INET, $me->{PORT}, $me->{ADDR}) ) or
		$me->Message("could not connect socket [$me->{HOST}, $me->{PORT}]: $!") and
			return 0;

	select((select($s) , $| = 1)[0]);  # autoflush

	defined($msg = <$s>) or $me->Message("Could not read") and return 0;
	chomp $msg;
	$me->Message($msg);
	$me->State('AUTHORIZATION');

	$me->User and $me->Pass and $me->Login;

} # end Connect

#******************************************************************************
#* 
#******************************************************************************
sub Login
{
	my $me = shift;
	my $s = $me->{SOCK};
	print $s "USER " , $me->User , $me->EOL;
	my $line = <$s>;
	chomp $line;
	$me->Message($line);
	$line =~ /^\+/ or $me->Message("USER failed: $line") and $me->State('AUTHORIZATION')
		and return 0;

	print $s "PASS " , $me->Pass , $me->EOL;
	$line = <$s>;
	chomp $line;
	$me->Message($line);
	$line =~ /^\+/ or $me->Message("PASS failed: $line") and $me->State('AUTHORIZATION')
		and return 0;
	$line =~ /^\+OK \S+ has (\d+) /i and $me->Count($1);

	$me->State('TRANSACTION');

	$me->POPStat() or return 0;

} # end Login

#******************************************************************************
#* Get the Head of a message number
#******************************************************************************
sub Head
{
	my $me = shift;
	my $num = shift;
	my $header = '';
	my $s = $me->{SOCK};

	$me->Debug and print "TOP $num 0\n";
	print $s "TOP $num 0", $me->EOL;
	my $line = <$s>;
	$me->Debug and print $line;
	chomp $line;
	$line =~ /^\+OK/ or $me->Message("Bad return from TOP: $line") and return '';
	$line =~ /^\+OK (\d+) / and $buflen = $1;
	
	do {
		$line = <$s>;
		$line =~ /^\s*$|^\.\s*$/ or $header .= $line;
	} until $line =~ /^\.\s*$/;

	return wantarray ? split(/\r?\n/, $header) : $header;
} # end Head

#******************************************************************************
#* Get the header and body of a message
#******************************************************************************
sub HeadAndBody
{
    my $me = shift;
	my $num = shift;
	my $mandb = '';
	my $s = $me->{SOCK};

	$me->Debug and print "RET $num\n";
	print $s "RETR $num", $me->EOL;
	my $line = <$s>;
	$me->Debug and print $line;
	chomp $line;
	$line =~ /^\+OK/ or $me->Message("Bad return from RETR: $line") and return '';
	$line =~ /^\+OK (\d+) / and $buflen = $1;
	
	do {
		$line = <$s>;
		$line =~ /^\.\s*$/ or $mandb .= $line;
	} until $line =~ /^\.\s*$/;

	return wantarray ? split(/\r?\n/, $mandb) : $mandb;

} # end HeadAndBody

#******************************************************************************
#* get the body of a message
#******************************************************************************
sub Body
{
	my $me = shift;
	my $num = shift;
	my $body = '';
	my $s = $me->{SOCK};
	
	$me->Debug and print "RET $num\n";
	print $s "RETR $num", $me->EOL;
	my $line = <$s>;
	$me->Debug and print $line;
	chomp $line;
	$line =~ /^\+OK/ or $me->Message("Bad return from RETR: $line") and return '';
	$line =~ /^\+OK (\d+) / and $buflen = $1;
	
	# skip the header
	do {
		$line = <$s>;
	} until $line =~ /^\s*$/;

	do {
		$line = <$s>;
		$line =~ /^\.\s*$/ or $body .= $line;
	} until $line =~ /^\.\s*$/;

	return wantarray ? split(/\r?\n/, $body) : $body;
   
} # end Body

#******************************************************************************
#* handle a STAT command
#******************************************************************************
sub POPStat {
	my $me = shift;
	my $s = $me->Socket;

	$me->Debug and carp "POP3: POPStat";
	print $s "STAT", $me->EOL;
	my $line = <$s>;
	$line =~ /^\+OK/ or $me->Message("STAT failed: $line") and return 0;
	$line =~ /^\+OK (\d+) (\d+)/ and $me->Count($1), $me->Size($2);

    return $me->Count();
}

#******************************************************************************
#* issue the LIST command
#******************************************************************************
sub List {
    my $me = shift;
	my $num = shift || '';

	my $s = $me->Socket;
	$me->Alive() or return;

	local @retarray = ();
	local $ret = '';

	$me->Debug and carp "POP3: List $num";
	print $s "LIST $num", $me->EOL;
	my $line = <$s>;
	$line =~ /^\+OK/ or $me->Message("$line") and return;
	if ($num) {
		$line =~ s/^\+OK\s*//;
		return $line;
	}
	while( defined( $line = <$s> ) ) {
		$line =~ /^\.\s*$/ and last;
		$ret .= $line;
		chomp $line;
		push(@retarray, $line);
	}
	if ($ret) {
		return wantarray ? @retarray : $ret;
	}
}

#******************************************************************************
#* retrieve the given message number
#******************************************************************************
sub Retrieve {
    my $me = shift;
	my $num = shift || return;

	$me->Alive or return;

	my $s = $me->Socket;
	
	
	local @retarray = ();
	local $ret = '';

	$me->Debug and print STDERR "DEBUG: RETR $num", $me->EOL;
	print $s "RETR $num", $me->EOL;
	my $line = <$s>;
	$line =~ /^\+OK\s*/ or $me->Message($line) and return;

	while( defined( $line = <$s> ) ) {
		$me->Debug and print STDERR "DEBUG: $line";
		$line =~ /^\.\s*$/ and last;
		$ret .= $line;
		chomp $line;
		push(@retarray, $line);
	}
	if ($ret) {
		return wantarray ? @retarray : $ret;
	}
		
	return;
}

#******************************************************************************
#* implement the LAST command - see the rfc (1081)
#******************************************************************************
sub Last {
    my $me = shift;
	
	my $s = $me->Socket;
	
	print $s "LAST", $me->EOL;
	my $line = <$s>;
	
	$line =~ /\+OK (\d+)\s*$/ and return $1;
}

#******************************************************************************
#* reset the deletion stat
#******************************************************************************
sub Reset {
    my $me = shift;
	
	my $s = $me->Socket;
	print $s "RSET", $me->EOL;
	my $line = <$s>;
	$line =~ /\+OK .*$/ and return 1;
	return 0;
}

#******************************************************************************
#* 
#******************************************************************************
sub Delete {
    my $me = shift;
	my $num = shift || return;

	my $s = $me->Socket;
	print $s "DELE $num",  $me->EOL;
	my $line = <$s>;
	$me->Message($line);
	$line =~ /^\+OK / && return 1;
	return 0;
}

# end package Mail::POP3Client

1;

