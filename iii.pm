#!/usr/bin/perl

package iii;

use strict;
use Expect; 
use Data::Dumper;
use Carp;

use constant STATE_UNDEFINED                => 0;
use constant STATE_MAIN_MENU                => 1;
use constant STATE_RECORD_OPEN              => 2;
use constant STATE_LIST_OPEN                => 3;
use constant STATE_OUTPUT_MARC              => 4;
use constant STATE_UPDATE_RECORDS           => 5;
use constant STATE_LIST_OUTPUT_FIELD_SELECT => 6;
use constant STATE_OUTPUT_HOST_SELECT       => 7;

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
  
  $self->{_state};
  
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
  
  $self->{_state} = STATE_MAIN_MENU;
  
  return 1;
}

sub logout {
  my $self = shift;
  
  if ( $self->{_state} != STATE_MAIN_MENU ) {
    confess 'Can only logout from main menu';
  }
  
  if ( $self->_blob() =~ /X \> DISCONNECT/ ) {
    $self->_s( 'x' );
  }
  else {
    $self->_s( 'q' );
  }
  
  sleep $self->{_timeout};
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
  
  if ( $self->{_state} != STATE_MAIN_MENU ) {
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
  $self->{_state} = STATE_UNDEFINED;
  
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
  
  $self->{_state} = STATE_LIST_OPEN;
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
  
  if ( $query_number !~ /^\d{1,4}$/ ) {
    confess 'Invalid query number';
  }
  
  if ( $query_name !~ /^.{1,60}$/ ) {
    confess 'Invalid query name';
  }
  
  if ( $self->{_state} != STATE_LIST_OPEN ) {
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

sub list_output_open {
  my $self = shift;
  
  if ( $self->{_state} != STATE_LIST_OPEN ) {
    confess 'iii:list_output() must only be called when a list is open';
  }
  
  $self->_seod( 'u', 'CREATE' );
  
  $self->{_state} = STATE_UNDEFINED;
  
  my @conditions = (
    [ 'maximum number of files' => sub {
      $self->_seod( ' ', 'CREATE' );
      $self->_seod( 'q', 'Display review' );
      $self->{_state} = STATE_LIST_OPEN;
      
      confess 'Output file list full';
    }],
    [ 'Output Item' => sub {} ]
  );
  
  $self->_seod( 'c', @conditions );

  $self->{_state} = STATE_LIST_OUTPUT_FIELD_SELECT;
}

sub list_output_send {
  my $self = shift;

  my $filename         = shift or confess 'Filename not specified';
  my $host             = shift or confess 'Host not specified';
  my $remote_username  = shift or confess 'Username not specified';
  my $remote_password  = shift or confess 'Password not specified';
  my $remote_path      = shift;

  if ( $self->{_state} != STATE_LIST_OUTPUT_FIELD_SELECT ) {
    confess 'iii:list_output_send() must only be called when a list is open for output';
  }
  
  $self->{_state} = STATE_UNDEFINED;
  
  my $initial_timeout = $self->{_timeout};
  $self->{_timeout} = 30;
  
  $self->_seod( chr(10), 'RECORD FORMAT' );
  $self->_seod( 'c', 'File name' );
  $self->_seod( $filename . chr(13), 'Output the file' );
  $self->_seod( 'y', 'Key a number' );
  
  $self->{_state} = STATE_OUTPUT_HOST_SELECT;
  $self->_output_login( $host, $remote_username, $remote_password, $remote_path );
  
  $self->{_timeout} = $initial_timeout;
  
  $self->_seod( 't', 'Enter name' );
  $self->_seod( $filename . chr(13), 'CONTINUE' );
  $self->_seod( 'c', 'Key a number' );
  $self->_seod( 'q', 'Your review file' );
  
  # delete the file on iii server
  $self->_seod( 'o', 'DELETE' );
  
  if ( $self->_blob() =~ /(\d+) \> $filename\.out/ ) {
    $self->_seod( 'd', 'Delete which' );
    $self->_seod( $1, 'Are you sure' );
    $self->_seod( 'y', 'OUTPUT' );
  }
  else {
    carp 'Could not delete file; continuing execution';
  }
  
  $self->_seod( 'q', 'Your review file' );
  $self->_seod( 'q', 'LIST RECORDS' );
  
  $self->{_state} = STATE_LIST_OPEN;
}

sub list_output_add_field {
  my $self = shift;
  
  my $field_number = shift;
  my $field_name   = shift;
  
  if ( $self->{_state} != STATE_LIST_OUTPUT_FIELD_SELECT ) {
    confess 'iii:list_output_add_field() must only be called when a list is open for output';
  }
  
  $self->{_state} = STATE_UNDEFINED;

  $self->_seod( $field_number, $field_name );
  
  $self->{_state} = STATE_LIST_OUTPUT_FIELD_SELECT;
}

sub list_output_add_field_marc {
  my $self = shift;
  
  my $marc_tag = shift;
  
  if ( $self->{_state} != STATE_LIST_OUTPUT_FIELD_SELECT ) {
    confess 'iii:list_output_add_field_marc() must only be called when a list is open for output';
  }

  $self->{_state} = STATE_UNDEFINED;

  $self->_seod( '!', 'MARC TAG' );
  $self->_seod( $marc_tag . chr(13), $marc_tag );
  
  $self->{_state} = STATE_LIST_OUTPUT_FIELD_SELECT;
}

sub list_add_condition {
  # $value must include a carriage return and
  # "All fields/At least one field" setting if applicable
  
  my $self       = shift;
  
  my $boolean    = shift or confess 'Boolean not specified';
  my $field_code = shift or confess 'Field code not specified';
  my $condition  = shift or confess 'Condition not specified';
  my $value      = shift or confess 'Value not specified';
  
  if ( $self->{_state} != STATE_LIST_OPEN ) {
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

sub list_set_range {
  my $self = shift;
  
  my $range_start = shift;
  my $range_end = shift;
  
  if ( $self->{_state} != STATE_LIST_OPEN ) {
    confess 'iii:list_set_range() must only be called when a list is open';
  }

  $self->{_state} = STATE_UNDEFINED;
  
  $self->_seod( '\\', 'Search records' );
  $self->_seod( 'n', 'Enter starting' );
  $self->_seod( $range_start . chr(13), 'Enter ending' );
  $self->_seod( $range_end . chr(13), 'Use scoped' );
  $self->_seod( 'n', 'correct' );
  $self->_seod( 'y', 'Enter action' );
  
  $self->{_state} = STATE_LIST_OPEN;
}

sub list_start {
  my $self = shift;
  my $list_name = shift or confess 'List name not specified';
  
  if ( $self->{_state} != STATE_LIST_OPEN ) {
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

  if ( $self->{_state} != STATE_LIST_OPEN ) {
    confess 'iii:list_from_saved() must only be called when a list is open';
  }

  $self->_seod( 'q', 'Select review file' );
  $self->{_state} = STATE_UNDEFINED;
  
  $self->_seod( 'q', 'MANAGEMENT' );
  
  $self->_seod( 'q', 'MAIN MENU' );
  $self->{_state} = STATE_MAIN_MENU;
}

sub output_marc_start {
  my $self = shift;
  
  if ( $self->{_state} != STATE_MAIN_MENU ) {
    confess 'Can only start output from main menu';
  }

  $self->_seod( 'a', 'ADDITIONAL' );
  
  $self->{_state} = STATE_UNDEFINED;
  
  $self->_seod( 'm', 'initials' );
  $self->_seod( $self->{_initials} . chr(13), 'password' );
  $self->_seod( $self->{_ipass} . chr(13), 'READ/WRITE' );
  $self->_seod( 'a', 'SEND a MARC file' );
  
  $self->{_state} = STATE_OUTPUT_MARC;
}

sub output_marc_create {
  my $self = shift;
  
  my $filename  = shift or confess 'Filename not specified';
  my $source    = shift or confess 'Source not specified';
  my $list_name = shift or confess 'List name not specified';
  my $overwrite = shift || 0;

  if ( $self->{_state} != STATE_OUTPUT_MARC ) {
    confess 'Must be at output MARC to create MARC file';
  }
  
  if ( $source ne 'b' && $source ne 'r' ) {  # boolean or range
    confess 'Invalid MARC record source';
  }
  
  $self->_seod( 'c', 'Enter name' );
  $self->{_state} = STATE_UNDEFINED;
  
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
      $self->{_state} = STATE_OUTPUT_MARC;
      
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
  
  $self->{_timeout} = 600;
  $self->_seod( 's', 'CONVERSION STATISTICS' );
  $self->{_timeout} = $initial_timeout;
  
  $self->_seod( 'q', 'SPACE' );
  $self->_seod( ' ', 'QUIT' );
  $self->_seod( 'q', 'SPACE' );
  $self->_seod( ' ', 'Output MARC' );
  
  $self->{_state} = STATE_OUTPUT_MARC;
  return 1;
}

sub output_marc_send {
  my $self = shift;
  
  my $filename         = shift or confess 'Filename not specified';
  my $host             = shift or confess 'Host not specified';
  my $remote_username  = shift or confess 'Username not specified';
  my $remote_password  = shift or confess 'Password not specified';
  my $remote_path      = shift;
  
  if ( $self->{_state} != STATE_OUTPUT_MARC ) {
    confess 'Must be at output MARC to send MARC file';
  }
  
  if ( ! ( $self->_blob() =~ /(\d+) \> $filename\.out\e/ ) ) {
    carp "Filename '$filename' not found";
    return 0;
  }
  
  my $file_number = $1;
  
  $self->_seod( 's', 'Enter file number' );
  
  $self->{_state} = STATE_UNDEFINED;
  
  my $initial_timeout = $self->{_timeout};
  $self->{_timeout} = 10;
  
  $self->_seod( $file_number, 'Key a number' );

  $self->{_state} = STATE_OUTPUT_HOST_SELECT;
  
  $self->_output_login( $host, $remote_username, $remote_password, $remote_path );
  
  $self->_seod( 't', 'Enter name' );

  $initial_timeout = $self->{_timeout};
  $self->{_timeout} = 600;
  $self->_seod( chr(13), 'CONTINUE' );
  $self->{_timeout} = $initial_timeout;
  
  $self->_seod( 'c', 'Choose one' );
  sleep $self->{_timeout};
  $self->_seod( 'q', 'SPACE' );
  $self->_seod( ' ', 'Output' );  
  
  $self->{_state} = STATE_OUTPUT_MARC;
  return 1;
}

sub output_marc_end {
  my $self = shift;
  
  if ( $self->{_state} != STATE_OUTPUT_MARC ) {
    confess 'Must be at output MARC to end outputting MARC';
  }

  $self->_seod( 'q', 'READ/WRITE' );

  $self->{_state} = STATE_UNDEFINED;

  $self->_seod( 'q', 'ADDITIONAL' );
  $self->_seod( 'q', 'MAIN MENU' );
  
  $self->{_state} = STATE_MAIN_MENU;
}

sub update_records_start {
  my $self = shift;
  my $record_type = shift || 'b';
  
  if ( $self->{_state} != STATE_MAIN_MENU ) {
    confess 'Must be at main menu to update records';
  }
  
  $self->{_state} = STATE_UNDEFINED;
  
  $self->_seod( 'd', 'DATABASE MAINTENANCE' );
  $self->_seod( 'u', 'initials' );
  $self->_seod( $self->{_initials} . chr(13), 'password' );
  $self->_seod( $self->{_ipass} . chr(13), 'Update:' );
  $self->_seod( $record_type, 'record do you want' );
  
  $self->{_state} = STATE_UPDATE_RECORDS;
}

sub update_records_end {
  my $self = shift;
  
  if ( $self->{_state} != STATE_UPDATE_RECORDS ) {
    confess 'Must be at update records to end updating records';
  }
  
  $self->{_state} = STATE_UNDEFINED;
  
  $self->_seod( chr(13), 'or QUIT' );
  $self->_seod( 'q', 'DATABASE MAINTENANCE' );
  $self->_seod( 'q', 'MAIN MENU' );
  
  $self->{_state} = STATE_MAIN_MENU;
}

sub record_open {
  my $self  = shift;
  my $index = shift;
  my $value = shift;
  
  if ( $self->{_state} != STATE_UPDATE_RECORDS ) {
    confess 'Must be at update records to open record';
  }
  
  $self->{_state} = STATE_UNDEFINED;
  
  my @expected = (
    [ 'To modify' => sub {} ],
    
    [ 'Waiting' => sub {
      carp 'Record in use: ' . $index . $value;
      $self->_s( ' ' );  # FIXME: should be _seod()
    }],
    
    [ 'would be here' => sub {
      carp 'Record does not exist: ' . $index . $value;
      $self->_s( 'q' );  # FIXME: should be _seod()
    }],

    [ 'deleted' => sub {
      carp 'Record deleted: ' . $index . $value;
      $self->_s( ' ' );  # FIXME: _seod()
    }],
    
    [ timeout => sub {
      # unexpected error
      confess 'Unknown state attempting to open ' . $index . $value;
    }]
  );
  
  $self->_seod( $index . $value . chr(13), @expected );
  
  $self->{_state} = STATE_RECORD_OPEN;
}

sub record_fixed_field {
  my $self      = shift;
  my $code      = shift;
  my $new_value = shift;
  
  my $old_value;
  
  if ( ! defined $code ) {
    confess 'Code must be defined';
  }
  
  if ( $self->{_state} != STATE_RECORD_OPEN ) {
    confess 'Must have record open to access fixed field';
  }

  if ( $self->_blob() =~ /(\d+) $code: ([\S]+)/ ) {
    $old_value = $2;
  }
  elsif ( $self->_blob() =~ /(\d+) $code:/ ) {
    $old_value = ' ';  # could be space or null; client code will need to handle
  }
  else {
    carp "Field '$code' not found";
  }
  
  if ( ! defined $new_value ) {    
    return $old_value;
  }
  
  $self->{_state} = STATE_UNDEFINED;
  
  $self->_seod( $1, $code );
  $self->_seod( $new_value, 'To modify' );
  
  $self->{_state} = STATE_RECORD_OPEN;
}

sub record_close {
  my $self      = shift;
  my $edit_mode = shift || 'e';
  
  if ( $self->{_state} != STATE_RECORD_OPEN ) {
    confess 'Must have record open to close record';
  }

  my @expected = (
    [ '<SPACE>' => sub { $self->_s(' '); exp_continue; }],  # invalid field
    [ 'EXIT'    => sub { $self->_s( $edit_mode ); }],       # record was modified
    [ 'QUIT'    => sub { $self->_s('q'); }],                # record was not modified
    [ timeout   => sub { $self->_s( $edit_mode ); }]
  );
  
  $self->_seod( 'q', @expected );
  $self->_eod( 'Record:' );
  
  $self->{_state} = STATE_UPDATE_RECORDS;
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

sub _output_login {
  my $self = shift;
  
  my $host             = shift or confess 'Host not specified';
  my $remote_username  = shift or confess 'Username not specified';
  my $remote_password  = shift or confess 'Password not specified';
  my $remote_path      = shift;
  
  if ( $self->{_state} != STATE_OUTPUT_HOST_SELECT ) {
    confess 'Current state does not support host selection';
  }
  
  $self->{_state} = STATE_UNDEFINED;

  if ( $self->_blob() !~ /(\d+) \> $host\e/ ) {
    carp "Host '$host' not found";
    
    $self->_seod( 'q', 'SPACE' );
    $self->_seod( ' ', 'Output MARC' );
    
    $self->{_state} = STATE_OUTPUT_MARC;
    return 0;
  }
  
  $self->_seod( $1, 'Username' );
  $self->_seod( $remote_username . chr(13), 'Password' );
  
  $self->_seod( $remote_password . chr(13), 'Put File At' );
  
  if ( $remote_path ) {
    $self->_seod( 'd', 'REMOTE' );
    $self->_seod( 'c', 'ENTER a path name' );
    $self->_seod( 'e', 'Enter path name' );
    $self->_seod( $remote_path . chr(13), 'Choose one' );  # TODO: does this work with multiple levels of directories?
    $self->_seod( 'v', 'Choose one' );
    sleep 5;
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
