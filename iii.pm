#!/usr/bin/perl

package iii;

use strict;
use Expect; 
use Data::Dumper;
use Carp;

sub new {
  my $class   = shift;
  my $self    = {};
  my %options = @_;

  # don't cluck/confess here as it prints the credentials
  $self->{_server}   = $options{'server'}   or croak 'Bad iii options';
  $self->{_protocol} = $options{'protocol'} or croak 'Bad iii options';
  $self->{_initials} = $options{'initials'} or croak 'Bad iii options';
  $self->{_ipass}    = $options{'ipass'}    or croak 'Bad iii options';
  
  # TODO: add support for installations which bypass login
  $self->{_login}    = $options{'login'}    or croak 'Bad iii options';
  $self->{_lpass}    = $options{'lpass'}    or croak 'Bad iii options';
  
  $self->{_output}   = $options{'output'} || 0;
  
  $self->{_at_main_menu} = 0;
  $self->{_list_is_open} = 0;
  $self->{_at_output_marc} = 0;
  
  $self->{_timeout} = defined $options{'timeout'} ? $options{'timeout'} : 2;
  
  $self->{_e} = new Expect( $self->{_protocol} . ' ' . $self->{_server} );
  
  bless ( $self, $class );
  return $self;
}

sub login {
  my $self  = shift;

  $self->{_e} = new Expect( $self->{_protocol} . ' ' . $self->{_server} );
  $self->{_e}->log_stdout( $self->{_output} );
  
  $self->_eod( 'login' );
  
  $self->_seod( $self->{_login} . chr(13), 'Password' );
  $self->_seod( $self->{_lpass} . chr(13), 'MAIN' );
  
  $self->{_at_main_menu} = 1;
  
  return 1;
}

sub logout {
  my $self = shift;
  
  if ( ! $self->{_at_main_menu} ) {
    confess 'Can only logout from main menu';
  }
  
  if ( $self->_blob() =~ /X \> DISCONNECT/ ) {
    $self->_s( 'x' );
  }
  else {
    $self->_s( 'q' );
  }
  
  sleep 2;
  $self->{_e}->hard_close();
}

sub output {
  my $self  = shift;
  my $value = shift;
  
  if ( $value == 0 || $value == 1 ) {
    $self->{_e}->log_stdout( $value );
  }
  else {
    confess 'Invalid setting for iii::output()';
  }
}

sub list_open {
  # opens list if name matches or is Empty
  my $self = shift;
  
  my $list_number = shift;
  my $list_name   = shift;
  
  if ( ! $self->{_at_main_menu} ) {
    confess 'iii:open_list() must only be called from the main menu';
  }
  
  if ( $list_number !~ /^\d+$/ ) {
    confess '$list_number must be an integer';
  }
  
  if ( ! defined $list_name ) {
    confess '$list_name required';
  }
  
  $list_number = sprintf( '%03d', $list_number );  # pad with zeroes
  
  $self->_seod( 'M', 'MANAGEMENT' );
  $self->{_at_main_menu} = 0;
  
  $self->_seod( 'L', 'initials' );
  $self->_seod( $self->{_initials} . chr(13), 'password' );
  $self->_seod( $self->{_ipass} . chr(13), 'NAME' );
  
  # FIXME: will very long names wrap to the next line and break this?
  my @expected = (
    [ 'locked this file' => sub { confess 'File locked' } ],
    [ 'file, ' . $list_name . ',' => sub {} ],  # has expected name
    [ 'Create a new' => sub {} ]  # is Empty
  );
  
  $self->_seod( $list_number, @expected );
  
  $self->{_list_is_open} = 1;
}

sub list_new {
  my $self = shift;
  my $type = shift;
  
  if ( $self->_blob() =~ /2 > Create/ ) {
    $self->_seod( '2', 'Choose what kind' );
  }
  else {
    $self->_seod( 'n', 'Are you sure' );
    $self->_seod( 'y', 'Choose what kind' );
  }
  
  $self->_seod( $type, 'BOOLEAN SEARCH' );
}

sub list_from_saved {
  my $self         = shift;
  my $query_number = shift;
  my $query_name   = shift;
  
  if ( ! $self->{_list_is_open} ) {
    confess 'iii:list_from_saved() must only be called when a list is open';
  }
  
  $self->_seod( '%', 'PREVIOUSLY' );
  
  my $query_found = 0;
  
  if ( $self->_blob() !~ /$query_number \> $query_name/ ) {
    for ( my $i = 0; $i < 10; $i++ ) {  # arbitrary number of tries
      if ( $self->_se( 'f', "$query_number > $query_name" ) ) {
        $query_found = 1;
        last;
      }
    }
  }

  if ( ! $query_found ) {
    confess 'Could not find specified query';
  }
  
  my @expected = (
    [ 'At least one field' => sub {
      $self->_seod( '1', 'Enter action' )
    } ],  # FIXME: kluge to get past this oddly-timed prompt
    
    [ 'that satisfy' => sub {} ]
  );
  
  $self->_seod( $query_number, @expected );
}

sub list_add_condition {
  # $value must include a carriage return and
  # "All fields/At least one field" setting if applicable
  
  my $self       = shift;
  
  my $boolean    = shift;
  my $field_code = shift;
  my $condition  = shift;
  my $value      = shift;
  
  if ( ! $self->{_list_is_open} ) {
    confess 'iii:list_from_saved() must only be called when a list is open';
  }
  
  if ( $boolean ) {
    $self->_seod( $boolean, 'Enter code' );
  }
  
  # TODO: allow for more complex fields like MARC
  $self->_seod( $field_code, 'boolean condition' );
  
  my @conditions = (
    [ ' = '             => sub {} ],
    [ ' <> '            => sub {} ],
    [ ' < '             => sub {} ],
    [ ' > '             => sub {} ],
    [ ' <= '            => sub {} ],
    [ ' >= '            => sub {} ],
    [ ' between '       => sub {} ],
    [ ' not within '    => sub {} ],
    [ ' has '           => sub {} ],
    [ ' does not have ' => sub {} ]
  );
  
  $self->_seod( $condition, @conditions );
  $self->_seod( $value, 'Enter action' );
}

sub list_start {
  my $self = shift;
  my $list_name = shift;
  
  if ( ! $self->{_list_is_open} ) {
    confess 'iii:list_from_saved() must only be called when a list is open';
  }

  $self->_seod( 's', 'What name' );
  $self->_seod( $list_name . chr(13), 'Type "s"' );
  
  my $initial_timeout = $self->{_timeout};
  
  $self->{_timeout} = 7200;  # one hour
  $self->_eod( 'SEARCH COMPLETE' );
  $self->{_timeout} = $initial_timeout;
  
  $self->_seod( ' ', 'LIST RECORDS' );
}

sub list_close {
  my $self = shift;

  if ( ! $self->{_list_is_open} ) {
    confess 'iii:list_from_saved() must only be called when a list is open';
  }

  $self->_seod( 'q', 'Select review file' );
  $self->{_list_is_open} = 0;
  
  $self->_seod( 'q', 'MANAGEMENT' );
  
  $self->_seod( 'q', 'MAIN MENU' );
  $self->{_at_main_menu} = 1;
}

sub output_marc_start {
  my $self = shift;
  
  if ( ! $self->{_at_main_menu} ) {
    confess 'Can only start output from main menu';
  }

  $self->_seod( 'a', 'ADDITIONAL' );
  
  $self->{_at_main_menu} = 0;
  
  $self->_seod( 'm', 'initials' );
  $self->_seod( $self->{_initials} . chr(13), 'password' );
  $self->_seod( $self->{_ipass} . chr(13), 'READ/WRITE' );
  $self->_seod( 'a', 'Output MARC' );
  
  $self->{_at_output_marc} = 1;
}

sub output_marc_create {
  my $self = shift;
  
  my $filename  = shift;
  my $source    = shift;
  my $list_name = shift;
  my $overwrite = shift || 0;

  my $list_number;
  
  if ( ! $self->{_at_output_marc} ) {
    confess 'Must be at output MARC to create MARC file';
  }
  
  if ( $source ne 'b' && $source ne 'r' ) {  # boolean or range
    confess 'Invalid MARC record source';
  }
  
  $self->_seod( 'c', 'Enter name' );
  $self->{_at_output_marc} = 0;
  
  my $already_exists;
  
  my @expected = (
    [ 'Specify records' => sub { $already_exists = 0; } ],
    [ 'already exists'  => sub { $already_exists = 1; } ]
  );
  
  $self->_seod( $filename . chr(13), @expected );
  
  if ( $already_exists ) {
    if ( $overwrite ) {
      $self->_seod( 'y', 'overwrite' );
      $self->_seod( 'y', 'Specify records' );
    }
    else {
      $self->_seod( 'n', 'CREATE' );
      $self->{_at_output_marc} = 1;
      
      carp "MARC file $filename already exists; not overwriting";
      return 0;
    }
  }
  
  @expected = (
    [ 'Select review file' => sub {} ],
    [ 'Present range'      => sub { confess 'not yet supported' } ]
  );
  
  $self->_seod( $source, @expected );
  
  while (1) {
    if ( $self->_blob() =~ /(\d+) \> $list_name\e/ ) {
      $list_number = $1;
      last;
    }
    
    $self->_s( 'f' );
    
    if ( ! $self->_e( ' > ' ) ) {
      last;
    }
  }
  
  if ( ! defined $list_number ) {
    carp "List '$list_name' not found";
    return 0;
  }
  
  $self->_seod( $list_number, 'START sending' );
  
  my $initial_timeout = $self->{_timeout};
  
  $self->{_timeout} = 120;
  $self->_seod( 's', 'CONVERSION STATISTICS' );
  $self->{_timeout} = $initial_timeout;
  
  $self->_seod( 'q', 'SPACE' );
  $self->_seod( ' ', 'QUIT' );
  $self->_seod( 'q', 'SPACE' );
  $self->_seod( ' ', 'Output MARC' );
  
  $self->{_at_output_marc} = 1;
  return 1;
}

sub output_marc_send {
  my $self = shift;
  
  my $filename  = shift or confess;
  my $host      = shift or confess;
  my $username  = shift or confess;
  my $password  = shift or confess;
  
  if ( ! $self->{_at_output_marc} ) {
    confess 'Must be at output MARC to send MARC file';
  }
  
  if ( ! $self->_blob() =~ /(\d+) \> $filename\e/ ) {
    carp "Filename '$filename' not found";
    return 0;
  }
  
  $self->_seod( 's', 'Enter file number' );
  
  $self->{_at_output_marc} = 0;
  
  $self->_seod( $1, 'FILE TRANSFER' );
  
  if ( ! $self->_blob() =~ /(\d+) \> $host\e/ ) {
    carp "Host '$host' not found";
    
    $self->_seod( 'q', 'SPACE' );
    $self->_seod( ' ', 'Output MARC' );
    
    $self->{_at_output_marc} = 1;
    return 0;
  }
  
  $self->_seod( $1, 'Username' );
  $self->_seod( $username . chr(13), 'Password' );
  
  my $initial_timeout = $self->{_timeout};
  
  $self->{_timeout} = 120;
  $self->_seod( $password . chr(13), 'SOMETHING' );  # TODO: when ftp issue resolved
  $self->{_timeout} = $initial_timeout;
  
  # TODO: finish when ftp issue resolved
  
  $self->{_at_output_marc} = 1;
  return 1;
}

sub output_marc_end {
  my $self = shift;
  
  if ( ! $self->{_at_output_marc} ) {
    confess 'Must be at output MARC to end outputting MARC';
  }

  $self->_seod( 'q', 'READ/WRITE' );

  $self->{_at_output_marc} = 0;

  $self->_seod( 'q', 'ADDITIONAL' );
  $self->_seod( 'q', 'MAIN MENU' );
  
  $self->{_at_main_menu} = 1;
}

sub _lines {
  my $self = shift;
  
  my @lines = split /\e/, $self->_blob();
  
  my @good_lines;
  
  foreach my $line ( @lines ) {
    if ( $line =~ /^\[[0-9]+;\dH(.*)$/ ) {
      push @good_lines, $line;
    }
  }
  
  return @good_lines;
}

sub _blob {
  my $self = shift;
  
  return $self->{_e}->before . $self->{_e}->match . $self->{_e}->after;
}

sub _s {
  my $self = shift;
  my $send = shift;
  
  $self->{_e}->send( $send );
}

sub _e {
  my $self     = shift;
  my @expected = @_;
  
  my $result = $self->{_e}->expect( $self->{_timeout}, @expected );
  
  if ( defined $result ) {
    return 1;
  }
  else {
    return 0;
  }
}

sub _se {
  # Send, Expect
  
  my $self = shift;
  
  my $send     = shift;
  my @expected = @_;
  
  $self->_s( $send );
  $self->_e( @expected );  
}

sub _eod {
  # Expect Or Die

  my $self     = shift;
  my @expected = @_;

  if ( ! $self->_e( @expected ) ) {
    confess 'Died at unExpected point';
  }
}

sub _seod {
  # Send, Expect Or Die
  
  my $self = shift;
  
  my $send     = shift;
  my @expected = @_;
  
  $self->_s( $send );
  $self->_eod( @expected );  
}

sub _dump {
  # for debugging
  
  my $self       = shift;
  my $value      = shift;
  my $should_die = shift || 0;
  
  open DUMP, '>>expect_dump.txt' or confess 'Error opening dump file';
  print DUMP $value;
  close DUMP;
  
  if ( $should_die ) {
    confess 'Dieing after dump';
  }
}

1;
