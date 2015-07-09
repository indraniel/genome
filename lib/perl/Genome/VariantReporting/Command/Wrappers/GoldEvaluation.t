#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Test::Exception;
use Genome::Test::Factory::Sample;
use Genome::Test::Factory::Library;
use Genome::VariantReporting::Command::Wrappers::TestHelpers qw(get_build);

my $pkg = "Genome::VariantReporting::Command::Wrappers::GoldEvaluation";

use_ok($pkg);

my $roi_name = "test roi";

# setup the samples
my $normal_sample = Genome::Test::Factory::Sample->setup_object();
my $tumor_sample = Genome::Test::Factory::Sample->setup_object();
my $gold_sample = Genome::Test::Factory::Sample->setup_object(name => "GOLD");

# setup the libraries
my $normal_library = Genome::Test::Factory::Library->setup_object(sample => $normal_sample);
my $tumor_library = Genome::Test::Factory::Library->setup_object(sample => $tumor_sample);
my $gold_library = Genome::Test::Factory::Library->setup_object(sample => $gold_sample);

# create the build
my $build1 = get_build($roi_name, $tumor_sample, $normal_sample);

subtest "sample and library labels" => sub {

    my $cmd = $pkg->create(
        model => $build1->model,
        gold_sample_name => "GOLD",
        snvs_input_vcf => Genome::Sys->create_temp_file_path,
        indels_input_vcf => Genome::Sys->create_temp_file_path,
    );

    $DB::single = 1;
    is_deeply(
        $cmd->get_common_translations(),
        get_expected_labels(),
        'Sample & Library labels are as expected'
    );
};


sub get_expected_labels {
    return {
        'library_name_labels' => {
            'library_name_1' => 'Normal-Library1(library_name_1)',
            'library_name_2' => 'Discovery-Library1(library_name_2)',
            'library_name_3' => 'Gold-Library1(library_name_3)',
        },
        'sample_name_labels' => {
            'GOLD'          => 'Gold(GOLD)',
            'sample_name_1' => 'Normal(sample_name_1)',
            'sample_name_2' => 'Discovery(sample_name_2)',
        }
    };
}

done_testing;


