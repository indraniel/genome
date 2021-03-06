#!/usr/bin/env genome-perl

use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Exception;
use above 'Genome';

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

my $pkg = 'Genome::Process';
use_ok($pkg) || die;

{
    package TestProcess;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class TestProcess {
        is => [$pkg],
    };
}
{
    package TestResult;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class TestResult {
        is => ['Genome::SoftwareResult'],
    };
}

my $p = TestProcess->create();
ok($p, "Created TestProcess object");

ok($p->software_revision, 'software_revision automatically set');
ok($p->status, 'status automatically set');
is($p->subclass_name, 'TestProcess', 'subclass_name is properly set');
ok(defined($p->created_at), 'created_at automatically set');
is(scalar(@{[$p->status_events]}), 1, 'one status_event created');

ok(! defined($p->started_at), 'started_at NOT automatically set');
ok(! defined($p->ended_at), 'ended_at NOT automatically set');

$p->update_status('Running');
ok(defined($p->started_at), 'updating status to "Running" sets started_at');
is(scalar(@{[$p->status_events]}), 2, 'two status_events created');
is($p->status, 'Running', 'Status was set properly');

$p->update_status('Crashed');
ok(defined($p->ended_at), 'updating status to "Crashed" sets ended_at');
is(scalar(@{[$p->status_events]}), 3, 'thee status_events created');

my @errors = $p->__errors__;
is(scalar(@errors), 1, "Found just one __errors__");
is_deeply([$errors[0]->properties], ['disk_allocation_id'],
    "Error is missing 'disk_allocation_id' value");

my $da = $p->create_disk_allocation;
is($p->create_disk_allocation, $da,
    "No new disk allocation created if one was already made");
@errors = $p->__errors__;
is(scalar(@errors), 0, "Found no __errors__ now that disk_allocation is set");

my $result = TestResult->create();
$result->add_user(user => $p, label => 'test');
is_deeply([$p->results], [$result],
    'Found TestResult via SoftwareResult::User relationship');

my $code_test_dir = __FILE__ . '.d';

my %tests = (
    identical  => {
        test_name  => 'Identical directories',
        diff_count => 0,
    },
    missing    => {
        test_name  => 'Missing file',
        diff_count => 1,
        diff_message => 'no file',
    },
    additional => {
        test_name  => 'Additional file',
        diff_count => 1,
        diff_message => 'no file',
    },
    changed    => {
        test_name  => 'File content changed',
        diff_count => 1,
        diff_message => 'files are not the same',
    },
    symlink    => {
        test_name  => 'One-level symlink',
        diff_count => 0,
    },
    symlink_changed => {
        test_name  => 'File content of symlink target changed',
        diff_count => 1,
        diff_message => 'symlinks are not the same',
    },
    deep_symlink => {
        test_name  => 'Two-level deep symlink',
        diff_count => 0,
    },
    circular_symlink => {
        test_name  => 'Circular symlink',
        diff_count => 1,
        diff_message => 'no file',
  },
);

while (my ($subdir, $test_info) = each %tests) {
    subtest $test_info->{test_name} => sub {
        my $original_dir = File::Spec->join($code_test_dir, 'original');
        my $other_dir    = File::Spec->join($code_test_dir, $subdir);
        my %diffs = $p->_compare_output_directories($original_dir, $other_dir, $p);
        is(scalar(keys %diffs), $test_info->{diff_count}, 'Number of differences as expected');
        if (scalar(keys %diffs) > 0) {
            like((values %diffs)[0], qr/$test_info->{diff_message}/, 'Diff message as expected');
        }
    };
}

done_testing();
