# Welcome

This Perl module facilitates automated interaction with Innovative Interface's character-based client for Millennium.

Sample scripts:

## create lists from saved queries

```perl
use strict;
use iii;

my @login_files = <~/.iii_login>;
# this comment to fix /the weird VIM syntax slash problem

open LOGIN_DATA, $login_files[0] or die;
my $login_string = <LOGIN_DATA>;
close LOGIN_DATA;

chomp $login_string;
my @login_fields = split "\t", $login_string;

my %options = (
  'server'    => 'library.touro.edu',
  'protocol'  => 'telnet',
  'login'     => $login_fields[0],
  'lpass'     => $login_fields[1],
  'initials'  => $login_fields[2],
  'ipass'     => $login_fields[3],
  'output'    => 0,
);

# my $last_run = time() - 60*60*24*1;  # yesterday
# 
# my @last_run_array = localtime( $last_run );
# 
# my $month = sprintf( '%02d', $last_run_array[4] + 1 );
# my $day   = sprintf( '%02d', $last_run_array[3] );
# my $year  = sprintf( '%02d', $last_run_array[5] + 1900 );
# $year = substr $year, -2;
# 
# $last_run = $month . $day . $year;

my $last_run = '090710';

my $iii = new iii( %options );
$iii->login();

# updates

print 'Compiling list for updates; this may take up to 60 minutes...' . chr(10);

$iii->list_open( '125', 'TC summon updates' );
$iii->list_new( 'b' );
$iii->list_from_saved( '19', 'TC summon updates' );

$iii->list_add_condition( 'a', '11', 'g', $last_run );
$iii->list_start( 'TC summon updates' );
$iii->list_close();

# deletes

print 'Compiling list for deletes; this may take up to 30 minutes...' . chr(10);

$iii->list_open( '117', 'TC summon deletes' );
$iii->list_new( 'b' );
$iii->list_from_saved( '21', 'TC summon deletes' );

$iii->list_start( 'TC summon deletes' );
$iii->list_close();

$iii->logout();
```

## send previously-made lists to a remote server

```perl
use strict;
use iii;

my @login_files = <~/.iii_login>;
# this comment to fix /the weird VIM syntax slash problem

open LOGIN_DATA, $login_files[0] or die;
my $login_string = <LOGIN_DATA>;
close LOGIN_DATA;

chomp $login_string;
my @login_fields = split "\t", $login_string;

my %options = (
  'server'    => 'library.touro.edu',
  'protocol'  => 'telnet',
  'login'     => $login_fields[0],
  'lpass'     => $login_fields[1],
  'initials'  => $login_fields[2],
  'ipass'     => $login_fields[3],
  'output'    => 1,
  'timeout'   => 5,
);

my $iii = new iii( %options );
$iii->login();

$iii->output_marc_start();
$iii->output_marc_create( 'summon_up', 'b', 'TC summon updates', 1 ) or die;
$iii->output_marc_create( 'summon_del', 'b', 'TC summon deletes', 1 ) or die;
$iii->output_marc_send( 'summon_up', 'ftp.summon.serialssolutions.com', 'someuser', 'somepass', 'updates' ) or die;
$iii->output_marc_send( 'summon_del', 'ftp.summon.serialssolutions.com', 'someuser', 'somepass', 'deletes' ) or die;
$iii->output_marc_end();

$iii->logout();
```

