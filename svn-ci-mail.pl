#!/usr/bin/env perl

#
# send svn commit notification mail.
#

use strict;
use warnings;
use Encode;
use Net::SMTP;
use Data::Dumper;

my $svnlook = 'svnlook';

my $smtp_host      = 'mailhost';
my $smtp_port      = 25;
my $smtp_user      = 'username';
my $smtp_pass      = 'password';
my $sender         = 'your@sender.address';
#my $to            = 'your@sendto.address';
my $to             = '';
my $subject_prefix = '[yourprj]';
my $bts_rev_url    = 'http://path/to/bts/changeset/%s';
my $bts_id_url     = 'http://path/to/bts/ticket/%s';

sub usage {
  die "Usage: $0 REPOS REV\n";
}

my $svn_dir = shift or usage;
my $svn_rev = shift or usage;

sub send_mail {
  my ($from, $to, $subject, $body) = @_;
  print encode('utf8',<<"END_MAIL");
From: $from
To: $to
Subject: $subject

$body
END_MAIL
  if ( $to && length($to) ) {
    $subject = Encode::encode( 'MIME-Header-ISO_2022_JP', $subject );
    $body    = Encode::encode( 'iso-2022-jp',             $body );
    my $smtp = Net::SMTP->new( $smtp_host, Port => $smtp_port, Timeout => 60 ) or die $!;
    $smtp->mail($from);
    $smtp->to($to);
    $smtp->auth( $smtp_user, $smtp_pass ) if ($smtp_pass);
    $smtp->data();
    $smtp->datasend("From: $from\n");
    $smtp->datasend("To: $to\n");
    $smtp->datasend("Content-Type: text/plain; charset=\"iso-2022-jp\"\n");
    $smtp->datasend("Content-Transfer-Encoding: 7bit\n");
    $smtp->datasend("Subject: $subject\n\n");
    $smtp->datasend($body);
    $smtp->dataend();
    $smtp->quit;
  }
}

sub svn_look {
  my $cmd = shift;
  my $s = decode( 'utf8', `$svnlook $cmd -r $svn_rev $svn_dir` );
  chomp($s);
  return $s;
}

#######
# main

my ($log) = map { s/\n+$//; $_ } ( svn_look('log') );
my $author = svn_look('author');

my $from = sprintf( '"%s" <%s>', svn_look('author'), $sender );
my $subject = $subject_prefix . "r$svn_rev - " . ( split( /\n/, $log ) )[0];
my $date = svn_look('date');

my $rev = "r$svn_rev";
$rev .= " " . sprintf( $bts_rev_url, $svn_rev ) if ($bts_rev_url);

my $tickets='none';
my @ticket_nums;
while ($log =~ /\(refs ([\d\s,#]*)\)/g){
  my @a=map { my $a = $_; $a =~ s/#//; $a } split(',', $1);
  push(@ticket_nums,@a);
}
if ( $#ticket_nums != -1 ){
  $tickets = join(
    "\n" . " " x 9,
    map {
      my $a = "#$_";
      $a .= " " . sprintf( $bts_id_url, $_ ) if ($bts_id_url);
      $a
    } @ticket_nums
  );
}

my ($changed) = map { s/\n/\n  /g; $_ } ( svn_look('changed') );

my $body = <<"ENDBODY";
$log

Author:  $author
Date:    $date
Rev:     $rev
Tickets: $tickets
Changed:
  $changed
ENDBODY

send_mail( $from, $to, $subject, $body );

