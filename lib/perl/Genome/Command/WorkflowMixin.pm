package Genome::Command::WorkflowMixin;

use strict;
use warnings;

use Genome;
use Genome::Utility::Text qw(justify find_diff_pos);
use Params::Validate qw(:types);
use Workflow;

use DateTime::Format::Strptime;
use Date::Calc "Delta_DHMS";
use JSON;
use YAML::XS;

class Genome::Command::WorkflowMixin {
    is => ['Genome::Command::WithColor'],
    has => [
        summary_threshold => {
            is => 'Int',
            is_optional => 1,
            default_value => 5,
            doc => 'Parallel by stages with this many steps will be summarized. Use zero to summarize every step. Use a negative value to never summarize.'
        },
        connectors => {
            is => 'Boolean',
            is_optional => 1,
            default_value => 0,
            doc => 'Display input/output connectors in workflow.'
        },
        depth => {
            is => 'Int',
            is_optional => 1,
            default_value => -1,
            doc => 'Maximum workflow child depth.  Negative means infinite.'
        },
        logs => {
            is => 'Boolean',
            is_optional => 1,
            default_value => 1,
            doc => 'Display path of error logs for running, crashed, and failed steps.',
        },
        workflow => {
            is => 'Boolean',
            is_optional => 1,
            default_value => 1,
            doc => 'Display workflow.',
        },
        COLUMN_WIDTH => {
            is => 'Number',
            default_value => 47,
        }
    ],
};

my %WORKFLOW_NAME_COLORS = (
    "inputconnector" => "white",
    "outputconnector" => "white",
);

my %CONNECTOR_NAMES = (
    "inputconnector" => 1,
    "outputconnector" => 1,
);


sub _display_workflow {
    my ($self, $handle, $workflow, $profile_flag) = @_;

    return unless $self->workflow;

    unless ($self->_display_workflow_header($handle, $workflow)) {
        return 0;
    }

    # datetime_parser only needed for calculating the elapsed time.
    my $datetime_parser = DateTime::Format::Strptime->new(
            pattern => '%Y-%m-%d %H:%M:%S',
            on_error => 'croak');
    $self->_display_workflow_children($handle, $workflow, $datetime_parser, $profile_flag);
    return;
}

sub _display_workflow_header {
    my ($self, $handle, $workflow) = @_;

    unless ($workflow) {
        return 0;
    }

    # workflow->current is the InstanceExecution
    my $ie = $workflow->current;

    my $format_str = <<EOS;
%s
%s %s
%s %s
%s %s

EOS
    print $handle sprintf($format_str,
        $self->_color_heading('Workflow'),
        map {$self->_pad_right($_, $self->COLUMN_WIDTH)} (
            $self->_color_pair('ID', $workflow->id),
            $self->_color_pair('Name', $workflow->name),
            $self->_color_pair('Started',
                $self->_clean_up_timestamp($ie->start_time)),
            $self->_color_pair('Ended', $self->_clean_up_timestamp($ie->end_time)),
            $self->_color_pair('User', $ie->user_name),
            $self->_color_pair('Cache ID', $workflow->cache_workflow_id),
        ),
    );
}

sub _display_workflow_children {
    my ($self, $handle, $workflow, $datetime_parser, $profile_flag) = @_;

    print $handle $self->_color_dim($self->_format_workflow_child_line(
            "ID", "Status", "LSF ID", "Start Time", "Time Elapsed", "Name", "Start Time"));

    my $ie = $workflow->current;
    my $start_time = $self->_clean_up_timestamp($ie->start_time);
    $self->_display_workflow_child($handle, $profile_flag, $workflow, $datetime_parser, 0,
            $start_time);

    1;
}

sub _display_workflow_child {
    my ($self, $handle, $profile_flag, $child, $datetime_parser, $nesting_level,
            $prev_start_time) = @_;

    my $status = $child->status;

    my ($start_time, $elapsed_time) = $self->_resolve_child_times(
        $child->start_time, $child->end_time, $status, $datetime_parser);

    if ($self->connectors || !$self->_is_connector($child->name)) {
        print $handle $self->_format_workflow_child_line($child->id, $status,
            $child->current->dispatch_identifier, $start_time, $elapsed_time,
            ('  'x$nesting_level) . $child->name, $prev_start_time);

        # note or show additional LSF resource usage stats (only for done jobs)
        my $dispatch_id = $child->current->dispatch_identifier;
        if ($profile_flag && $dispatch_id && $dispatch_id =~ /^\d+$/ && $status eq 'done') {

            # collect LSF stats
            my $lsf_stats = $self->_fetch_lsf_resource_stats($dispatch_id);

            # record overall LSF stats
            $self->_track_overall_lsf_resource_stats($lsf_stats);

            # display LSF stat details
            if (keys %{$lsf_stats}) {
                $self->_display_lsf_resource_stats($handle, $lsf_stats);
            }
        }
    }

    if ($self->depth < 0 || $nesting_level < $self->depth) {
        if ($child->can('related_instances')) {
            my @subchildren = $child->related_instances;
            my $summary_bunches = $self->get_summary_bunches(\@subchildren);
            for my $bunch (@$summary_bunches) {
                $self->summarize(
                    child_bunch => $bunch,
                    handle => $handle,
                    datetime_parser => $datetime_parser,
                    nesting_level => $nesting_level + 1,
                    start_time => $start_time,
                    profile_flag => $profile_flag
                );
            }
        }
    }

    1;
}

sub get_summary_bunches {
    my $self = shift;
    my $steps = shift;

    my %step_names;
    for my $step (@$steps) {
        push @{$step_names{$step->name}}, $step;
    }
    return parallel_by_aware_sorted(values %step_names);
}


sub parallel_by_aware_sorted {
    my @bunches = @_;

    my %parallel_by_bunches;
    my @normal_bunches;
    for my $bunch (@bunches) {
        if ($bunch->[0]->name =~ /(.*) \(Parallel By\)/) {
            $parallel_by_bunches{$1} = $bunch;
        } else {
            push @normal_bunches, $bunch;
        }
    }

    my @sorted_bunches = sort sort_by_start_time @normal_bunches;

    my @final_bunches;
    for my $bunch (@sorted_bunches) {
        if (exists($parallel_by_bunches{$bunch->[0]->name})) {
            push @final_bunches, $parallel_by_bunches{$bunch->[0]->name};
        }
        push @final_bunches, $bunch;
    }
    return \@final_bunches;
}

sub sort_by_start_time {
    my $first_time = $a->[0]->start_time;
    my $second_time = $b->[0]->start_time;
    if (defined($first_time) and defined($second_time)) {
        return $first_time cmp $second_time;
    } elsif (defined($first_time)) {
        return -1;
    } elsif (defined($second_time)) {
        return 1;
    } else {
        return 0;
    }
}

sub summarize {
    my $self = shift;
    my %p = Params::Validate::validate(@_, {
        child_bunch => { type => ARRAYREF, },
        handle => { type => HANDLE, },
        datetime_parser => { isa => 'DateTime::Format::Strptime', },
        nesting_level => { type => SCALAR, },
        start_time => { type => SCALAR, },
        profile_flag => { type => SCALAR, },
    });
    if ($self->_should_summarize($p{child_bunch})) {
        $self->_write_summary(
            child_bunch => $p{child_bunch},
            handle => $p{handle},
            nesting_level => $p{nesting_level},
        );
    } else {
        for my $child (@{$p{child_bunch}}) {
            $self->_display_workflow_child(
                $p{handle}, $p{'profile_flag'}, $child, $p{datetime_parser},
                $p{nesting_level}, $p{start_time},
            );
        }
    }
}

sub _should_summarize {
    my ($self, $child_bunch) = @_;

    if ((scalar(@$child_bunch) >= $self->summary_threshold) and
        ($self->summary_threshold >= 0)) {
        return 1;
    } else {
        return 0;
    }
}

my @STATUSES = qw(
    new
    scheduled
    running
    running*
    crashed
    done
);

sub _write_summary {
    my $self = shift;
    my %p = Params::Validate::validate(@_, {
        child_bunch => { type => ARRAYREF, },
        handle => { type => HANDLE, },
        nesting_level => { type => SCALAR, },
    });

    my %counts;
    for my $child (@{$p{child_bunch}}) {
        my $status = $child->status;
        $counts{$status}++;
    }
    my @strings;
    for my $status (@STATUSES) {
        if (exists($counts{$status})) {
            push @strings, sprintf('%s(%d)',
                $self->_status_color($status), $counts{$status});
        }
        delete $counts{$status};
    }
    # tack on any other (new) statuses
    for my $status (keys %counts) {
        push @strings, sprintf('%s(%d)',
            $self->_status_color($status), $counts{$status});
    }


    my $nesting_level = $p{nesting_level};
    my $handle = $p{handle};
    printf $handle "%s  %s%s\n",
        justify(join(' ', @strings), 'right', 64),
        '  ' x $nesting_level, ($p{child_bunch}->[0])->name;
}

# -- additional helper functions --
sub _is_connector {
    my ($self, $workflow_name) = @_;

    my $stripped_workflow_name = $self->_strip_key($workflow_name);

    return exists $CONNECTOR_NAMES{$stripped_workflow_name};
}

# Returns formatted strings for start time and elapsed time.
sub _resolve_child_times {
    my ($self, $raw_start_time, $raw_end_time, $status, $datetime_parser) = @_;

    unless ($raw_start_time) {
        return ('', '');
    }

    my $start_time = $self->_clean_up_timestamp($raw_start_time);
    my $start_datetime = $datetime_parser->parse_datetime($start_time);

    unless ($start_datetime) {
        return ('', '');
    }

    my $end_datetime;
    my $elapsed_time_color;
    if ($raw_end_time) {
        $end_datetime = $datetime_parser->parse_datetime(
            $self->_clean_up_timestamp($raw_end_time));
    } elsif ("running" eq $self->_strip_key($status)) {
        $end_datetime = $self->_resolve_running_child_end_time();
        $elapsed_time_color = $self->_status_colors('running');
    } else {
        return ('', '');
    }

    if (defined $end_datetime) {
        my $elapsed_time = $self->_resolve_duration(
            $start_datetime, $end_datetime);
        return $start_time, $self->_color($elapsed_time, $elapsed_time_color);
    }
    return $start_time, '';
}

sub _resolve_running_child_end_time {
    my ($self) = @_;

    return DateTime->now(time_zone=>'local');
}

sub _format_workflow_child_line {
    my ($self, $id, $status, $dispatch_id, $start_time, $elapsed_time, $name, $prev_start_time) = @_;
    $dispatch_id = $self->_format_dispatch_id($dispatch_id);
    return sprintf("%s %s %s %s %s  %s\n",
        $self->_pad_right($id, 9),
        $self->_status_color($self->_pad_right($status, 9)),
        $dispatch_id,
        $self->_color_time_since_prev_start_time($start_time, $prev_start_time, 19),
        $self->_workflow_elapsed_color(
            $self->_pad_left($elapsed_time, 13), $name, $dispatch_id),
        $self->_workflow_name_color($name));
}

sub _color_time_since_prev_start_time {
    my ($self, $start_time, $prev_start_time, $width) = @_;

    my $prev_str = $self->_pad_right($prev_start_time, $width);
    my $start_str = $self->_pad_right($start_time, $width);

    my @diff_pos = find_diff_pos($prev_str, $start_str);
    my $result;
    if (scalar(@diff_pos)) {
        my $first_diff = $diff_pos[0];
        $result = $self->_color_dim(substr($start_str, 0, $first_diff));
        $result .= substr($start_str, $first_diff);
    } else {
        $result = $start_str;
    }
    return $result;
}

sub _format_dispatch_id {
    my ($self, $dispatch_id) = @_;
    $dispatch_id = ' ' unless defined($dispatch_id);
    $dispatch_id =~ s/^P\d+/shortcut/;

    $dispatch_id = $self->_pad_right($dispatch_id, 10);
    if($dispatch_id =~ /shortcut/) {
        $dispatch_id = $self->_color($dispatch_id, 'white');
    }
    return $dispatch_id
}

sub _workflow_name_color {
    my ($self, $text) = @_;
    return $self->_colorize_text_by_map($text, $text, %WORKFLOW_NAME_COLORS);
}

sub _workflow_elapsed_color {
    my ($self, $text, $workflow_name, $dispatch_id) = @_;
    if($dispatch_id =~ /shortcut/) {
        return $self->_color($text, 'white');
    } else {
        return $self->_colorize_text_by_map($text, $workflow_name,
            %WORKFLOW_NAME_COLORS);
    }
}

sub _resolve_duration {
    my ($self, $d1, $d2) = @_;

    my ($days, $hours, $minutes, $seconds) = Delta_DHMS(
        $d1->year, $d1->month, $d1->day, $d1->hour, $d1->minute, $d1->second,
        $d2->year, $d2->month, $d2->day, $d2->hour, $d2->minute, $d2->second);

    my $day_string   = $self->_pad_left($days   ? $days."d":"", 4);

    return sprintf("$day_string %02d:%02d:%02d", $hours, $minutes, $seconds);
}

sub _pad_left {
    my ($self, $arg, $length) = @_;
    return justify($arg, 'right', $length);

}

sub _pad_right {
    my ($self, $arg, $length) = @_;
    return justify($arg, 'left', $length);
}

sub _clean_up_timestamp {
    my ($self, $dirty_stamp) = @_;

    unless (defined $dirty_stamp) {
        return '';
    }

    my ($clean_stamp) = split('\.', $dirty_stamp);
    $clean_stamp =~ s/\s$//;
    return $clean_stamp;
}

sub _display_logs {
    my ($self, $handle, $workflow) = @_;

    return unless $self->logs;
    return unless $workflow;

    my @error_log_paths;
    my @step_names;
    my @step_statuses;
    for my $step ($self->unfinished_workflow_steps($workflow)) {
        if($step->current->can('stderr')) {
            my $error_path = $step->current->stderr || ' ';
            if(-e $error_path and -s $error_path) {
                push(@error_log_paths, $error_path);
                push(@step_names, $step->name);
                push(@step_statuses, $step->status);
            }
        }
    }

    if(@error_log_paths) {
        printf $handle "\n%s\n", $self->_color('Error Logs:', 'bold');
        for my $i (0..$#error_log_paths) {
            my $status = $step_statuses[$i];
            my $name = $step_names[$i];
            my $length = 22;
            if(length($name) > $length) {
                $name = substr($name, 0, $length-3) . "...";
            }
            my $log_path = $error_log_paths[$i];

            # print logfile of running/crashed steps
            printf $handle "%s %s %s\n",
                    $self->_status_color($status),
                    justify($name, 'left', $length),
                    $log_path;

            $self->_print_error_log_preview($handle, $log_path);
        }
    }
    return;
}

sub unfinished_workflow_steps {
    my ($self, $workflow) = @_;

    my @bucket;
    _recursively_find_unfinished_steps($workflow, \@bucket);
    return @bucket;
}

sub _recursively_find_unfinished_steps {
    my ($child, $bucket) = @_;
    my $status = $child->status;

    if($status eq 'failed' or $status eq 'crashed' or
       $status eq 'running' or $status eq 'running*') {
        push(@{$bucket}, $child);
    }

    if ($child->can('related_instances')) {
        for my $subchild ($child->related_instances) {
            _recursively_find_unfinished_steps($subchild, $bucket);
        }
    }
    return;
}

sub _print_error_log_preview {
    my ($self, $handle, $log_path) = @_;

    # If the log is less than 5MB, try to find the error message
    my @error_lines;
    if ( (-s $log_path) < (5 * 1024 * 1024) ) {
        @error_lines = `grep --max-count=1 'ERROR' $log_path`;
    } else {
        print $handle " Max file size exceeded, skipped error preview.\n";
    }

    my $preview;
    if (@error_lines) {
        $preview = $error_lines[0];
    } else {
        $preview = `tail -n 1 $log_path`;
        chomp($preview);
    }

    # terminate any unfinished color regions in preview
    $preview .= $self->_color(' ', 'white');

    # get_terminal_width() appears to be a case of object schizophrenia, it
    # comes from Genome::Command::Viewer.
    my $screen_width = $self->get_terminal_width();
    if (length($preview) > $screen_width - 20) {
        $preview = substr($preview, 0, $screen_width - 20) . "...";
    }

    if (@error_lines) {
        print $handle $self->_color_pair("  First Error", $preview) . "\n";
    } else {
        print $handle $self->_color_pair("  Last Line", $preview) . "\n";
    }
}

sub _fetch_lsf_resource_stats {
    my ($self, $dispatch_id) = @_;

    my $bmetrica = '/gscuser/idas/bin/bmetrica';
    my $cmd = "$bmetrica jobstats $dispatch_id";
#    print "---> execing '$cmd'\n";
    my $json = qx($cmd);
#    print "---> JSON String\n", $json, "\n";
    my $data = JSON::decode_json($json);
    my $job_stats = $data->[0];
#    print "---> Perl Hash\n", Dump($job_stats), "\n";
    return $job_stats;
}

sub _display_lsf_resource_stats {
    my ($self, $handle, $stats) = @_;

    my $format_str = <<EOS;
    %s
    %s %s
    %s %s
    %s %s
    %s
    %s %s

    %s
    %s
    %s
    %s
    
    %s
    %s
    %s
    %s

    %s
    %s
    %s

    %s
    %s
    %s
    %s
    %s

    %s

EOS

    my $mem_reqd   = $self->_lsf_memory_display($stats->{'MemRequested'});
    my $mem_resrvd = $self->_lsf_memory_display($stats->{'MemReserved'});

    my $mem_used   = $self->_lsf_memory_display($stats->{'MaxMem'});
    my $swp_used   = $self->_lsf_memory_display($stats->{'MaxSwap'});

    my $res_requirements = $self->_lsf_resource_display($stats->{'ResRequirements'});

    my $cpu_time = $self->_lsf_timing_display($stats->{'CpuUsed'});
    my $run_time = $self->_lsf_timing_display($stats->{'RunTime'});
    my $sys_time = $self->_lsf_timing_display($stats->{'SysTime'});
    my $usr_time = $self->_lsf_timing_display($stats->{'UserTime'});

    print $handle sprintf($format_str,
        $self->_color_heading('LSF Basic Info'),
        map {$self->_pad_right($_, $self->COLUMN_WIDTH)} (
            $self->_color_pair('Job ID', $stats->{'JobId'}),
            $self->_color_pair('Job PID', $stats->{'JobPid'}),
            $self->_color_pair('Submitter', $stats->{'User'}),
            $self->_color_pair('Executor', $stats->{'ExecUser'}),
            $self->_color_pair('Queue', $stats->{'Queue'}),
            $self->_color_pair('Execution Host', $stats->{'ExecHost'}),
            $self->_color_pair('Submit Time', $stats->{'SubmitTime'}),
            $self->_color_pair('Start Time', $stats->{'StartTime'}),
            $self->_color_pair('End Time', $stats->{'EndTime'}),
        ),

        $self->_color_heading('LSF Submission Info'),
        $self->_color_pair('Mem Requested', $mem_reqd),
        $self->_color_pair('Mem Reserved', $mem_resrvd),
        $self->_color_pair('Resource Requirements', $res_requirements),

        $self->_color_heading('Host Metrics'),
        $self->_color_pair('# Nodes', $stats->{'NumNodes'}),
        $self->_color_pair('# PIDs Used', $stats->{'NumPids'}),
        $self->_color_pair('# Threads', $stats->{'NumThreads'}),

        $self->_color_heading('Memory Usage'),
        $self->_color_pair('Mem Used', $mem_used),
        $self->_color_pair('Swp Used', $swp_used),

        $self->_color_heading('System Timings'),
        $self->_color_pair('CPU Time', $cpu_time),
        $self->_color_pair('Run Time', $run_time),
        $self->_color_pair('Sys Time', $sys_time),
        $self->_color_pair('Usr Time', $usr_time),

        $self->_color_pair(
            'Efficiency (CPU Utilization)',
            sprintf("%.2f", $stats->{'Efficiency'})
        ),
   );
}

sub _lsf_resource_display {
    my ($self, $resource) = @_;
    $resource ||= '';
    $resource =~ s/\\u003e/>/;
    $DB::single = 1;
    return $resource;
}

sub _lsf_timing_display {
    my ($self, $elapsed_secs) = @_;
    $elapsed_secs ||= 0;
    my ($secs, $mins, $hrs, $days) = ($elapsed_secs,
                                      $elapsed_secs/60,
                                      $elapsed_secs/60/60,
                                      $elapsed_secs/60/60/24);

    my $timings = sprintf("%.2f (secs) %.2f (mins) %.2f (hrs) %.2f (days)",
                          $secs, $mins, $hrs, $days);
    return $timings;
}

sub _lsf_memory_display {
    my ($self, $max_mem_kb) = @_;
    $max_mem_kb ||= 0;
    my ($mem_kb, $mem_mb, $mem_gb) = ($max_mem_kb, $max_mem_kb/1024, $max_mem_kb/1024/1024);
    my $mem = sprintf("%.2f (kb) %.2f (mb) %.2f (gb)", $mem_kb, $mem_mb, $mem_gb);
    return $mem;
}

{
    my ($total_mem_kb, $total_swap_kb) = (0, 0);
    my ($total_cpu_time, $total_run_time, $total_sys_time, $total_usr_time) =
      (0, 0, 0, 0);

    sub _track_overall_lsf_resource_stats {
        my ($self, $job_stats) = @_;
        
        # Memory Stats
        my $mem = $job_stats->{'MaxMem'} || 0;
        my $swp = $job_stats->{'MaxSwap'} || 0;

        $total_mem_kb += $mem;
        $total_swap_kb += $swp;

        # Timing Stats
        my $cpu = $job_stats->{'CpuUsed'} || 0;
        my $run = $job_stats->{'RunTime'} || 0;
        my $sys = $job_stats->{'SysTime'} || 0;
        my $usr = $job_stats->{'UserTime'} || 0;

        $total_cpu_time += $cpu;
        $total_run_time += $run;
        $total_sys_time += $sys;
        $total_usr_time += $usr;

        
    }

    sub _display_overall_lsf_resource_usage {
        my ($self, $handle) = @_;

        # format the results
        my $mem_used = $self->_lsf_memory_display($total_mem_kb);
        my $swp_used = $self->_lsf_memory_display($total_swap_kb);

        my $cpu_time = $self->_lsf_timing_display($total_cpu_time);
        my $run_time = $self->_lsf_timing_display($total_run_time);
        my $sys_time = $self->_lsf_timing_display($total_sys_time);
        my $usr_time = $self->_lsf_timing_display($total_usr_time);

        my $format_str = <<EOS;

    %s
    %s
    %s
    
    %s
    %s
    %s
    %s
    %s
EOS

        print $handle $self->_color_heading('Overall Build LSF Usage'), "\n";
        print $handle sprintf($format_str,
            $self->_color_heading('Memory Usage'),
            $self->_color_pair('Mem Used', $mem_used),
            $self->_color_pair('Swp Used', $swp_used),

            $self->_color_heading('System Timings'),
            $self->_color_pair('CPU Time', $cpu_time),
            $self->_color_pair('Run Time', $run_time),
            $self->_color_pair('Sys Time', $sys_time),
            $self->_color_pair('Usr Time', $usr_time),
        );
    }
}


1;
