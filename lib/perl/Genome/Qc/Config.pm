package Genome::Qc::Config;

use strict;
use warnings;
use Genome;

class Genome::Qc::Config {
    is => 'UR::Value',
    id_by => [
        name => {
            is => 'String',
        },
    ],
};

sub get_commands_for_alignment_result {
    my $self = shift;
    my $is_capture = shift;

    my %config = (
        picard_collect_gc_bias_metrics => {
            class => 'Genome::Qc::Tool::Picard::CollectGcBiasMetrics',
            params => {
                input_file => 'bam_file',
                refseq_file => 'reference_sequence',
                assume_sorted => 1,
                use_version => 1.123,
                output_file=> 'output_file',
                chart_output => 'chart_output',
            },
        },
        picard_mark_duplicates => {
            class => 'Genome::Qc::Tool::Picard::MarkDuplicates',
            params => {
                output_file => 'output_file',
                input_file => 'bam_file',
                use_version => 1.123,
            },
        },
        picard_collect_multiple_metrics => {
            class => 'Genome::Qc::Tool::Picard::CollectMultipleMetrics',
            params => {
                input_file => 'bam_file',
                reference_sequence => 'reference_sequence',
                use_version => 1.123,
            },
        },
        samtools_flagstat => {
            class => 'Genome::Qc::Tool::Samtools::Flagstat',
            params => {
                'bam-file' => 'bam_file',
            },
        },
    );

    if ($is_capture) {
        $config{picard_calculate_hs_metrics} = {
            class => 'Genome::Qc::Tool::Picard::CalculateHsMetrics',
            params => {
                input_file => 'bam_file',
                bait_intervals => 'bait_intervals', #region_of_interest_set
                target_intervals => 'target_intervals', #target_region_set
                use_version => 1.123,
            },
        };
    }
    else {
        $config{picard_collect_wgs_metrics} = {
            class => 'Genome::Qc::Tool::Picard::CollectWgsMetrics',
            params => {
                input_file => 'bam_file',
                reference_sequence => 'reference_sequence',
                use_version => 1.123,
            },
        };
    }

    return \%config;
}

1;

