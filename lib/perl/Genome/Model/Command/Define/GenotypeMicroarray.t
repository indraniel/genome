#!/usr/bin/env genome-perl

use strict;
use warnings;

use above "Genome";

use Data::Dumper 'Dumper';
use File::Slurp;
use File::Temp;
use Genome::Model::Command::Define::GenotypeMicroarray;
use Test::More;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use_ok("Genome::Model::Command::Define::GenotypeMicroarray") or die;
use_ok('Genome::Model::GenotypeMicroarray::Test') or die;

no warnings;
*Genome::Report::Email::send_report = sub{ return 1; }; # so we don't get emails
*UR::Context::commit = sub{ return 1; }; # NO_COMMIT is not working in G:M:C:Services:Build:Run and actually commits
use warnings;

my $tempdir = File::Temp::tempdir(CLEANUP => 1);
my $temp_wugc = $tempdir."/genotype-microarray-test.wugc";

my $project = Genome::Project->create(name => '__TEST_PROJECT__');
ok($project, 'create project');

my $vl_build = Genome::Model::GenotypeMicroarray::Test->variation_list_build;
ok($vl_build, 'got reference sequence build');

my $test_model_name = "genotype-ma-test-".Genome::Sys->username."-".$$;
my $ppname = Genome::Model::GenotypeMicroarray::Test->processing_profile->name;
my $sample = Genome::Model::GenotypeMicroarray::Test->sample;

write_file($temp_wugc,"1\t72017\t72017\tA\tA\tref\tref\tref\tref\n1\t311622\t311622\tG\tA\tref\tSNP\tref\tSNP\n1\t314893\t--\n");

# attempt to define command w/o reference is an error
my $gm = Genome::Model::Command::Define::GenotypeMicroarray->create(
    processing_profile_name => $ppname,
    subject_name            => $sample->name,
    model_name              => $test_model_name .".test",
);
$gm->dump_status_messages(1);
ok(!$gm->execute(), 'attempt to define command w/o variation list build is an error');
$gm->delete;

# success
$gm = Genome::Model::Command::Define::GenotypeMicroarray->create(
    processing_profile_name => $ppname ,
    subject_name            => $sample->name,
    model_name              => $test_model_name .".test",
    dbsnp_build             => $vl_build,
    add_to_projects         => [$project],
);
$gm->dump_status_messages(1);
ok($gm->execute(),'define model');

# check for the model with the name
my $model = Genome::Model->get(name => $test_model_name.".test");
is($model->name,$test_model_name.".test", 'expected test model name retrieved');
my @projects = $model->projects;
is_deeply(\@projects, [$project], 'added a project');
$model->delete;

done_testing(8);
