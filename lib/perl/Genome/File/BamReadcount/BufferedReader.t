#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above 'Genome';
use Test::Exception;
use Test::More;

my $pkg = 'Genome::File::BamReadcount::BufferedReader';
use_ok($pkg);

my $test_dir = __FILE__.".d";
my $input_file = File::Spec->join($test_dir, "in.brct");

subtest 'read two in order' => sub {
    my $reader = $pkg->new($input_file);
    my $entry1 = $reader->get_entry(21, 1);
    my $entry2 = $reader->get_entry(21, 2);
    is($entry1->{_position}, 1, "Entry 1 is correct");
    is($entry2->{_position}, 2, "Entry 2 is correct");
};

subtest 'read two out of order' => sub {
    my $reader = $pkg->new($input_file);
    my $entry2 = $reader->get_entry(21, 2);
    my $entry1 = $reader->get_entry(21, 1);
    is($entry1->{_position}, 1, "Entry 1 is correct");
    is($entry2->{_position}, 2, "Entry 2 is correct");
};

subtest 'read two across a chromosome boundary' => sub {
    my $reader = $pkg->new($input_file);
    my $entry3 = $reader->get_entry(21, 3);
    my $entry2 = $reader->get_entry(22, 2);
    is($entry3->{_position}, 3, "Entry 3 is correct");
    is($entry2->{_position}, 2, "Entry 2 is correct");
};

subtest 'read something not in the file' => sub {
    my $reader = $pkg->new($input_file);
    my $entry1 = $reader->get_entry(21, 4);
    is($entry1, undef, "Can't get something not in the file");
};

subtest 'read something past the end of the file' => sub {
    my $reader = $pkg->new($input_file);
    my $entry1 = $reader->get_entry('X', 5);
    is($entry1, undef, "Can't get something not in the file");
};

subtest 'read chromosome out of order' => sub {
    my $reader = $pkg->new($input_file);
    my $entry1 = $reader->get_entry(22, 2);
    dies_ok(sub {$reader->get_entry(21, 1)}, "Can't read an entry whose chromosome has already been read");
};

subtest 'read positions out of order beyond buffer' => sub {
    my $reader = $pkg->new($input_file);
    my $entry1 = $reader->get_entry(21, 3);
    dies_ok(sub {$reader->get_entry(21, 1)}, "Can't read back more than one");
};

subtest 'Detect duplicate entries' => sub {
    my $input_file_with_duplicates = File::Spec->join($test_dir, "duplicates.brct");
    my $reader = $pkg->new($input_file_with_duplicates);
    my $entry1 = $reader->get_entry(21, 1);
    dies_ok(sub {$reader->get_entry(21, 2)}, "Tried to read in a duplicate entry");
};

subtest 'Get the correct entry across chromosome boundary' => sub {
    my $input_file = File::Spec->join($test_dir, "in2.brct");
    my $reader = $pkg->new($input_file);
    my $entry1 = $reader->get_entry(21, 1);
    is($entry1->{_position}, 1, "Entry 1 position is correct");
    is($entry1->{_chromosome}, 21, "Entry 1 chromosome is correct");
    my $entry2 = $reader->get_entry(22, 2);
    is($entry2->{_position}, 2, "Entry 2 position is correct");
    is($entry2->{_chromosome}, 22, "Entry 2 chromosome is correct");
};

subtest 'Get first item in chromosome after missing last item in previous chromosome' => sub {
    my $reader = $pkg->new($input_file);
    my $entry1 = $reader->get_entry(21, 4);
    is($entry1, undef, "Can't get something not in the file");
    my $entry2 = $reader->get_entry(22, 2);
    is($entry2->{_position}, 2, "Entry 2 is correct");
};

subtest 'Get the correct entry across chromosome boundary' => sub {
    my $input_file = File::Spec->join($test_dir, "in2.brct");
    my $reader = $pkg->new($input_file);
    my $entry1 = $reader->get_entry(21, 1);
    is($entry1->{_position}, 1, "Entry 1 position is correct");
    is($entry1->{_chromosome}, 21, "Entry 1 chromosome is correct");
    my $entry2 = $reader->get_entry(22, 2);
    is($entry2->{_position}, 2, "Entry 1 position is correct");
    is($entry2->{_chromosome}, 22, "Entry 1 chromosome is correct");
};

subtest 'Get the correct entry across chromosome boundary part 2' => sub {
    my $input_file = File::Spec->join($test_dir, "in2.brct");
    my $reader = $pkg->new($input_file);
    my $entry1 = $reader->get_entry(21, 1);
    is($entry1->{_position}, 1, "Entry 1 position is correct");
    is($entry1->{_chromosome}, 21, "Entry 1 chromosome is correct");
    my $entry2 = $reader->get_entry(21, 3);
    is($entry2, undef, "Entry 2 is not present");
    lives_ok(sub {my $entry3 = $reader->get_entry(21, 4)}, "Got an entry even when reader crossed chrom boundary");
};

subtest "Can't go backwards even across chrom boundaries" => sub {
    my $input_file = File::Spec->join($test_dir, "in2.brct");
    my $reader = $pkg->new($input_file);
    my $entry1 = $reader->get_entry(21, 1);
    is($entry1->{_position}, 1, "Entry 1 position is correct");
    is($entry1->{_chromosome}, 21, "Entry 1 chromosome is correct");
    my $entry2 = $reader->get_entry(21, 3);
    is($entry2, undef, "Entry 2 is not present");
    dies_ok(sub {$reader->get_entry(21, 1)}, "Failed when we tried to go backwards");
};
done_testing;

