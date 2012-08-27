#!/usr/bin/perl

use strict;
use warnings;

require CFS::DB;
require CFS::PastGame::Manager;
require CFS::School;
require CFS::SchoolsRepoleMapping;

my $cfsdb = CFS::DB->new(default_connect_options=>{RaiseError=>1,PrintError=>1}) or die;

my %fcs_cache = ();
my $fcs_school = 'FCS School';

die "I need a lines.csv!" unless $ARGV[0];

while ( my $lines_csv = shift ) {
	open CSV, $lines_csv or die "Can't open() $lines_csv: $!";

	my $line = <CSV>;
	chomp $line;

	# sanity check - make sure we're looking at lines.csv
	my $hdr_str = 'Date,Visitor,Visitor Score,Home Team,Home Score,Line';
	die "First line is unexpected - expecting: $hdr_str"
		unless $line eq $hdr_str;

	while ( my $line = <CSV> ) {
		chomp $line;
		next if $line eq $hdr_str;

		my $year = '';
		my ($date, $v_team, $v_score, $h_team, $h_score, $spread ) = split /,/, $line
			or die "Failed to split line: $line";

		next if $spread eq ' ';
		unless ( $spread =~ m/^(-)?\d+([.]\d+)?$/o ) {
			warn "Invalid line ($spread): $line";
			next;
		}

		# extract season and reformat date
		if ( $date =~ m/^(\d\d)\/(\d\d)\/(\d\d\d\d)$/o ) {
			$year = $3;
			$year = $3 - 1 if $1 == 1;
			$date = sprintf '%0.4d-%0.2d-%0.2d', $3, $1, $2;
		}

		# make sure the teams exist
		my $h_school = CFS::School->new(db => $cfsdb, name => $h_team );
		my $v_school = CFS::School->new(db => $cfsdb, name => $v_team );
		unless ( $h_school->load(speculative => 1) ) {
			my $mapping = CFS::SchoolsRepoleMapping->new(db => $cfsdb, repole_name => $h_team);
			unless ( $mapping->load(speculative => 1) ) {
				warn "Failed to find $h_team ... skipping: $line";
				next;
			}
			$h_team = $mapping->name;
		}
		unless ( $v_school->load(speculative => 1) ) {
			my $mapping = CFS::SchoolsRepoleMapping->new(db => $cfsdb, repole_name => $v_team);
			unless ( $mapping->load(speculative => 1) ) {
				warn "Failed to find $v_team ... skipping: $line";
				next;
			}
			$v_team = $mapping->name;
		}

		my $gm_record = CFS::PastGame->new( db => $cfsdb,
			season => $year,
			gm_date => $date,
			t1_name => $h_team,
			t2_name => $v_team
		);

		unless ( $gm_record->load(speculative => 1) ) {
			$gm_record->t1_name($v_team);
			$gm_record->t2_name($h_team);
			$spread = - $spread;
			unless ( $gm_record->load(speculative => 1) ) {
				warn "Failed to find game $date / $h_team / $v_team: $line";
				next;
			}
		}

		$gm_record->line($spread);
		$gm_record->save;
	}
}
