#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

use_ok('Genome::Model::GenePrediction::Command::Eukaryotic::CodingGenesToGff') or die;

my $test_data_dir = Genome::Config::get('test_inputs') . '/Genome-Model-GenePrediction-Eukaryotic/';
ok(-d $test_data_dir, "test data dir exists at $test_data_dir") or die;

my $test_output_dir = File::Temp::tempdir('Genome-Model-GenePrediction-Eukaryotic-XXXXX', TMPDIR => 1, CLEANUP => 1);
ok(-d $test_output_dir, "test output dir exists at $test_output_dir") or die;

my $expected_output_file = $test_data_dir . "/expected_output2.gff";
ok(-e $expected_output_file, "expected output file $expected_output_file exists") or die;

my $output_file_fh = File::Temp->new(
    DIR => $test_output_dir,
    TEMPLATE => 'egap_gff_file_XXXXXXX',
);
my $output_file = $output_file_fh->filename;
$output_file_fh->close;

my $gff_object = Genome::Model::GenePrediction::Command::Eukaryotic::CodingGenesToGff->create(
    prediction_directory => $test_data_dir,
    output_file => $output_file,
);
ok($gff_object, "created coding gene to gff command object") or die;

my $rv = $gff_object->execute;
ok($rv, "coding gene to gff converted executed successfully") or die;;

ok(-s $output_file, "output file $output_file has size") or die;;

my $expected_md5 = Genome::Sys->md5sum($expected_output_file);
my $actual_md5 = Genome::Sys->md5sum($output_file);
ok($expected_md5 eq $actual_md5, "output file $output_file matches expected output $expected_output_file");

done_testing();
