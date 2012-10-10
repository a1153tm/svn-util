#!/usr/bin/env perl

#
# watch svn commits and send commits email.
#
# synopsys:
#   $ svn info <repo> > <repo>.info
#   $ svn-ci-watch.pl <repo>.info

use strict;
use warnings;
use Encode;
use Net::SMTP;
use XML::Simple;
use Data::Dumper;

$ENV{'LANG'}='C';
$ENV{'LC_CTYPE'}='C';

my $svn = 'svn';

my $smtp_host      = 'mailhost';
my $smtp_port      = 25;
my $smtp_user      = 'username';
my $smtp_pass      = 'password';
my $sender         = 'your@sender.address';
#my $to            = 'your@sendto.address';
my $to             = '';
my $subject_prefix = '[yourprj]';
my $bts_rev_url    = 'http://path/to/bts/chnangeset/%s';
my $bts_id_url     = 'http://path/to/bts/ticket/%s';

sub usage {
  die "Usage: $0 SVN-INFO\n";
}

my $info_name = shift or usage;

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
    my $smtp = Net::SMTP->new( $smtp_host, Port => $smtp_port, Timeout => 60 );
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

sub svn_read_info {
  my $fname=shift;
  open my $fh, "<$fname" or die "$info_name: $!";
  my @info=<$fh>;
  close $fh;
  my ($rev)=map{ /^Revision:\s*(\d+)/ } grep (/^Revision:/,@info)
    or die 'svn_read_info: not contained "Revision:" tag'; 
  my ($url)=map{ /^URL:\s*(.+)/ } grep (/^URL:/,@info)
    or die 'svn_read_info: not contained "URL:" tag'; 
  return ($rev,$url);
}

sub svn_write_info {
  my ($fname,$url,$rev)=@_;
  my $info=`$svn info -r $rev $url`;
  open my $fh, ">$fname" or die "$fname: $!";
  print $fh $info . "\n";
  close $fh;
}

sub svn_read_log {
  my ($url,$rev)=@_;
  my $log=`$svn log --xml -v -r $rev $url`;
  my $xml= XMLin($log);
  die "svn_read_log: xml parse error\n" if (! $xml->{logentry});
  my $x_path=$xml->{logentry}->{paths}->{path};
  my @paths;
  if (ref $x_path eq "ARRAY"){
    foreach (@$x_path){ push(@paths,sprintf "%s %s", decode('utf8',$_->{action}), decode('utf8',$_->{content})); }
  }else{
    $_=$x_path;
    push(@paths,sprintf "%s %s", decode('utf8',$_->{action}), decode('utf8',$_->{content}));
  }

  my ($r,$author,$date,$msg)=(
    decode('utf8',$xml->{logentry}->{revision}),
    decode('utf8',$xml->{logentry}->{author}),
    decode('utf8',$xml->{logentry}->{date}),
    decode('utf8',$xml->{logentry}->{msg}),
  );
  return ($r,$author,$date,\@paths,$msg);
}

sub svn_ci_mail {
  my $rev=shift;
  my $author=shift;
  my $date=shift;
  my $paths=shift;
  my $msg=shift;
  my ($summary) = split(/\n/,$msg);

  my $from="\"$author\" <$sender>";
  my $subject = "r$rev - $summary";
  $subject = $subject_prefix . $subject if ($subject_prefix);

  # make body
  my $tickets = "none";
  my @ticket_nums;
  while ($msg =~ /\(refs ([\d\s,#]*)\)/g){
    my @a = map { my $a=$_; $a=~ s/#//; $a  } split(',',$1);
    push(@ticket_nums,@a);
  }
  if ($#ticket_nums != -1){
    $tickets = "";
    $tickets .= "\n  " if ( $#ticket_nums > 0 ) ;
    $tickets .= join("\n  ",
      map {
        my $a="#$_" ;
        $a.=" ($bts_id_url/$_)" if ($bts_id_url);
        $a
      } @ticket_nums
    );
  }

  my $revision = "r$rev";
  $revision .= " ($bts_rev_url/$rev)" if ($bts_rev_url);

  my $changed = "  " . join("\n  ",@$paths);

  my $body = <<"ENDBODY";
Log: r$rev

$msg
Author:   $author
Date:     $date
Revision: $revision
Tickets:  $tickets
Changed:
$changed
ENDBODY
  return ($from, $subject, $body);
}

#######
# main 

# read svn info file
print Dumper($info_name),"\n";
my ($rev,$url)=&svn_read_info($info_name);
print "$info_name: Revision:$rev, URL:$url\n";

# get first update
$rev++;
my @revs=map { /^r(\d+)/ } grep(/^r/, `$svn log -q -r $rev:HEAD $url`)
  or die "new revision is not found\n";

# send ci mail
foreach (@revs) {
  $_=decode('utf8',$_);
  my ($r,$author,$date,$path,$msg)=&svn_read_log($url,$_);
  my ($from,$subject,$body)=&svn_ci_mail($r,$author,$date,$path,$msg);
  send_mail($from, $to, $subject, $body);
  $rev=$r;
}

svn_write_info($info_name,$url,$rev);

