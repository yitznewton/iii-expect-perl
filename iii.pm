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
  
  my $list_number = shift or confess 'List number not specified';
  my $list_name   = shift or confess 'List name not specified';
  
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
  my $type = shift or confess 'List type not specified';
  
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
  my $query_number = shift or confess 'Query number not specified';
  my $query_name   = shift or confess 'Query name not specified';
  
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
  
  my $boolean    = shift or confess 'Boolean not specified';
  my $field_code = shift or confess 'Field code not specified';
  my $condition  = shift or confess 'Condition not specified';
  my $value      = shift or confess 'Value not specified';
  
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
  my $list_name = shift or confess 'List name not specified';
  
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
  
  my $filename  = shift or confess 'Filename not specified';
  my $source    = shift or confess 'Source not specified';
  my $list_name = shift or confess 'List name not specified';
  my $overwrite = shift || 0;

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
  
  my $list_number = $self->_list_number( $list_name );
  
  if ( ! $list_number ) {
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
  
  my $filename  = shift or confess 'Filename not specified';
  my $host      = shift or confess 'Host not specified';
  my $username  = shift or confess 'Username not specified';
  my $password  = shift or confess 'Password not specified';
  
  if ( ! $self->{_at_output_marc} ) {
    confess 'Must be at output MARC to send MARC file';
  }
  
  if ( ! ( $self->_blob() =~ /(\d+) \> $filename\.out\e/ ) ) {
    carp "Filename '$filename' not found";
    return 0;
  }
  
  my $file_number = $1;
  
  $self->_seod( 's', 'Enter file number' );
  
  $self->{_at_output_marc} = 0;
  
  $self->_seod( $file_number, 'FILE TRANSFER' );
  
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

sub _list_number {
  # scans a list of review files for one with a given name -
  # for use within other functions where only non-empty lists
  # are displayed, so the list number is unpredictable.
  # GOTCHA: list name must be unique
  
  my $self      = shift;
  my $list_name = shift or confess 'List name not specified';
  
  while (1) {
    if ( $self->_blob() =~ /(\d+) \> $list_name\e/ ) {
      return $1;
    }
    
    $self->_s( 'f' );
    
    if ( ! $self->_e( ' > ' ) ) {
      return 0;
    }
  }
}

sub _blob {
  my $self = shift;
  
  return $self->{_e}->before . $self->{_e}->match . $self->{_e}->after;
}

sub _s {
  my $self = shift;
  my $send = shift or confess 'Input not specified';
  
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
  
  my $send     = shift or confess 'Input not specified';
  my @expected = @_ or confess 'No conditions specified';
  
  $self->_s( $send );
  $self->_e( @expected );  
}

sub _eod {
  # Expect Or Die

  my $self     = shift;
  my @expected = @_ or confess 'No conditions specified';

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
