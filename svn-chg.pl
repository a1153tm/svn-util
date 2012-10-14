#!/usr/bin/perl

# svn-chg.pl: output svn commits and code changes report.

use Getopt::Std;
use strict;
use warnings;

my $svn='svn';

sub HELP_MESSAGE{
  die "$0 [-r rev1:rev2] <svnurl>\n";
}
my %opts;
HELP_MESSAGE unless(getopts('r:',\%opts));
my $url=shift or HELP_MESSAGE;
my $revs=$opts{'r'} || "HEAD:1";

sub svn_diff{
  my ($url,$rev)=@_;
  my $diffopt = "--diff-cmd diff -x \'-U 0 -b -i -w -B\'";
  #my $diffopt = "-x \'-u -b --ignore-eol-style\'";
  open my $fh, "$svn diff -c $rev $diffopt $url|" or die "svn_diff:$?";
  my $add = 0;
  my $del = 0;
  while(<$fh>){
    $del++ if (/^-(?!-)/);
    $add++ if (/^\+(?!\+)/);
  }
  close $fh;
  return ($add,$del);
}

sub svn_changes{
  my ($url, $rev) = @_;
  my @chgs;
  open my $fh, "$svn log -q $url -r $rev|" or die "svn_changes:$?";
  while(<$fh>) {
    if ( m/^r(\d*)\s\|\s(\S*)\s\|\s(\d{4})-(\d{2})-(\d{2})/ ) {
      my ($rev,$author,$y,$m,$d)=($1,$2,$3,$4,$5);
      my ($add,$del) = &svn_diff($url,$rev);
      push(@chgs,[$rev,$author,$y,$m,$d,$add,$del]);
      printf "%4s|%10s|%4d-%02d-%02d|%4d|%4d\n",$rev,$author,$y,$m,$d,$add,$del;
    }
  }
  close $fh;
  return @chgs;
}

######
# main

my %dates=();
my %authors=();
my @chgs=svn_changes($url,$revs);
foreach(@chgs){
  my ($rev,$author,$y,$m,$d,$add,$del) = @{$_};
  my $ym = "$y-$m";
  my ($t_add,$t_del,$t_cnt) = ($add,$del,1);
  if ($dates{$ym}){
    my ($a,$d,$c) = @{$dates{$ym}};
    $t_add += $a;
    $t_del += $d;
    $t_cnt += $c;
  }
  $dates{$ym} = [$t_add,$t_del,$t_cnt];
  my ($a_add,$a_del,$a_cnt) = ($add,$del,1);
  if ($authors{$author}){
    my ($a,$d,$c) = @{$authors{$author}};
    $a_add += $a;
    $a_del += $d;
    $a_cnt += $c;
  }
  $authors{$author} = [$a_add,$a_del,$a_cnt];
}

my $str='';
$str .= "\n"
  . " month      | commits | add    | del    | delta  \n"
  . " -----------+---------+--------+--------+--------\n";

foreach my $ym (sort {$b cmp $a} keys %dates){
  my ($add,$del,$cnt) = @{$dates{$ym}};
  $str  .= sprintf " %-10s | %7d | %+6d | %+6d | %+6d\n"
    ,$ym,$cnt,$add,-$del,$add-$del;
}

$str .= "\n"
 . " author     | commits | add    | del    | delta  \n"
 . " -----------+---------+--------+--------+--------\n";

foreach my $author (sort keys %authors){
  my ($add, $del, $cnt) = @{$authors{$author}};
  $str .= sprintf " %-10s | %7d | %+6d | %+6d | %+6d\n"
    ,$author,$cnt,$add,-$del,$add-$del;
}

print $str,"\n";

