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
    die 'iii:open_list() must only be called from the main menu';
  }
  
  if ( $list_number !~ /^\d+$/ ) {
    die '$list_number must be an integer';
  }
  
  if ( ! defined $list_name ) {
    die '$list_name required';
  }
  
  $list_number = sprintf( '%03d', $list_number );  # pad with zeroes
  
  $self->_seod( 'M', 'MANAGEMENT' );
  $self->{_at_main_menu} = 0;
  
  $self->_seod( 'L', 'initials' );
  $self->_seod( $self->{_initials} . chr(13), 'password' );
  $self->_seod( $self->{_ipass} . chr(13), 'NAME' );
  
  # FIXME: will very long names wrap to the next line and break this?
  my @expected = (
    [ 'file, ' . $list_name . ',' => sub {} ],  # has expected name
    [ 'Create a new' => sub {} ]  # is Empty
  );
  
  $self->_seod( $list_number, @expected );
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

  my $self   = shift;
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

sub _edump {
  # for debugging
  
  my $self = shift;
  $self->_dump( $self->_blob() );
}

sub _dump {
  my $self  = shift;
  my $value = shift;
  
  open EDUMP, '>expect_dump.txt' or die 'Error opening dump file';
  
  print EDUMP $value;
  
  confess 'Dieing after dump';
}

1;

