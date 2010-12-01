#!/usr/bin/perl

package iii;

use strict;
use Expect; 
use Data::Dumper;
use Carp;

sub new {
  my $class = shift;
  my $self = {};

  $self->{_server}   = shift;
  $self->{_initials} = shift;
  $self->{_ipass}    = shift;
  $self->{_login}    = shift;  # TODO: add support for installations which bypass login
  $self->{_lpass}    = shift;
  
  $self->{_at_main_menu} = 1;
  $self->{_list_is_open} = 0;
  
  $self->{_timeout}  = shift || 2;
  
  $self->{_e} = new Expect( 'telnet ' . $self->{_server} );
  
  bless ( $self, $class );
  return $self;
}

sub login {
  my $self  = shift;

  $self->_eod( 'login' );
  
  $self->_seod( $self->{_login} . chr(13), 'Password' );
  $self->_seod( $self->{_lpass} . chr(13), 'MAIN' );
  
  $self->{_at_main_menu} = 1;
  
  return 1;
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
  
  my $self  = shift;
  my $value = shift;
  
  open DUMP, '>expect_dump.txt' or confess 'Error opening dump file';
  print DUMP $value;
  close DUMP;
  
  confess 'Dieing after dump';
}

1;

