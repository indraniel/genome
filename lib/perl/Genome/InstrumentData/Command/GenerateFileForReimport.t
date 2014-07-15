#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use strict;
use warnings;

use above "Genome";

use Genome::Utility::Test 'compare_ok';
use Test::More;

use_ok('Genome::InstrumentData::Command::GenerateFileForReimport') or die;

my $test_dir = Genome::Utility::Test->data_dir_ok('Genome::InstrumentData::Command::GenerateFileForReimport', 'v1');
my $expected_source_files_tsv = $test_dir.'/source_files.tsv';
my $expected_source_files_with_new_source_files_tsv = $test_dir.'/source_files.with_new_source_files.tsv';

my $library = Genome::Library->__define__(name => '__TEST_LIBRARY__');
my @instrument_data;
my $instdata_id = -100;
for my $format (qw/ bam fastq /) {
    my $instrument_data = Genome::InstrumentData::Imported->create(
        id => --$instdata_id,
        library => $library,
        subset_name => '2-AAXXAA',
        import_format => $format,
        user_name => 'apipe-builder',
        run_name => 'hiseq',
        lane => 2,
        original_data_path => '/a/'.$format,
        random => 'yep',
    );
    die 'Failed to create instrument data' if not $instrument_data;

    my $volume = Genome::Disk::Volume->get(mount_path => $test_dir);
    if ( not $volume ) {
        $volume = Genome::Disk::Volume->__define__(mount_path => $test_dir, disk_status => 'active');
    }

    my $alloc = Genome::Disk::Allocation->__define__(
        owner => $instrument_data,
        mount_path => $volume->mount_path,
        group_subdirectory => $format,
        allocation_path => '',
    );
    die "Failed to define allocation for genotype file!" if not $alloc;

    push @instrument_data, $instrument_data;
}

my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
my $file = $tmpdir.'/source-files.tsv';
my $generate = Genome::InstrumentData::Command::GenerateFileForReimport->create(
    instrument_data => \@instrument_data,
    file => $file,
);
ok($generate, 'create generate file for reimport');
ok($generate->execute, 'execute');
compare_ok($file, $expected_source_files_tsv, 'file matches');
#print "$file\n"; <STDIN>;

# With new source files...
# failures
$generate = Genome::InstrumentData::Command::GenerateFileForReimport->create(
    instrument_data => \@instrument_data,
    file => $file,
    instrument_data_and_new_source_files => [ 'mal-formed' ],
);
ok($generate, 'create generate file for reimport w/ new source files that are malformed');
my @errors = $generate->__errors__;
is(@errors, 1, 'correct number of errors');
is($errors[0]->desc, 'Mal-formed instrument data and new source files! mal-formed', 'correct error message');

$generate = Genome::InstrumentData::Command::GenerateFileForReimport->create(
    instrument_data => \@instrument_data,
    file => $file,
    instrument_data_and_new_source_files => [ $instrument_data[0]->id.'=does_not_exist', ],
);
ok($generate, 'create generate file for reimport w/ new source files that do not exist');
@errors = $generate->__errors__;
is(@errors, 1, 'correct number of errors');
is($errors[0]->desc, 'Source file does not exist! does_not_exist', 'correct error message');

# success
my $new_bam = $test_dir.'/new-source-files/new.bam';
my $new_fq1 = $test_dir.'/new-source-files/new.1.fastq';
my $new_fq2 = $test_dir.'/new-source-files/new.2.fastq';
$file = $tmpdir.'/source-files.with_new.tsv';
$generate = Genome::InstrumentData::Command::GenerateFileForReimport->create(
    instrument_data => \@instrument_data,
    file => $file,
    instrument_data_and_new_source_files => [ 
        $instrument_data[0]->id.'='.$new_bam,
        $instrument_data[1]->id.'='.$new_fq1,
        $new_fq2,
    ],
);
ok($generate, 'create generate file for reimport w/ new source files');
ok($generate->execute, 'execute');
compare_ok($file, $expected_source_files_with_new_source_files_tsv, 'file matches');
#print "$file\n"; <STDIN>;

done_testing();
